###Converted for glue compatibility 
import sys
import json
import gzip
import re
import io
import os
from typing import List, Dict, Any, Optional, Tuple
import boto3
import pandas as pd
import numpy as np
from datetime import datetime
from urllib.parse import urlparse

# For AWS Glue compatibility
from awsglue.transforms import *
from awsglue.utils import getResolvedOptions
from pyspark.context import SparkContext
from awsglue.context import GlueContext
from awsglue.job import Job
from awsglue.dynamicframe import DynamicFrame

# For embedding generation - packaged as a wheel in S3
import torch
from sentence_transformers import SentenceTransformer

# For vector storage - FAISS index will be stored in S3
import faiss
import pickle

class GlueLogProcessor:
    def __init__(self, 
                 glue_context,
                 model_name: str = "all-MiniLM-L6-v2", 
                 vector_dim: int = 384,
                 s3_model_path: Optional[str] = None):
        """
        Initialize the log processor with embedding model and vector storage
        
        """
        self.glue_context = glue_context
        self.spark = glue_context.spark_session
        
        # Initialize S3 client
        self.s3 = boto3.client('s3')
        
        # Initialize embedding model
        self.model_name = model_name
        self.vector_dim = vector_dim
        self.model = SentenceTransformer(model_name)
        
        # Initialize FAISS index
        self.index = None
        self.log_data = []
        
        # Load existing model if path provided
        if s3_model_path:
            self.load_from_s3(s3_model_path)
        else:
            # Create new index
            self.index = faiss.IndexFlatL2(vector_dim)
            
    def parse_logs_from_s3(self, s3_path: str) -> Tuple[List[Dict[str, Any]], pd.DataFrame]:
        """
        Parse logs from S3 location (supports JSON, GZIP)
        """
        parsed_logs = []
        
        # Parse S3 URI
        parsed_uri = urlparse(s3_path)
        bucket = parsed_uri.netloc
        key = parsed_uri.path.lstrip('/')
        
        # Handle directory vs file
        if not key.endswith('.json') and not key.endswith('.gz'):
            # List objects in directory
            response = self.s3.list_objects_v2(Bucket=bucket, Prefix=key)
            files = [obj['Key'] for obj in response.get('Contents', [])]
        else:
            # Single file
            files = [key]
            
        # Process each file
        for file_key in files:
            if not (file_key.endswith('.json') or file_key.endswith('.gz')):
                continue
                
            # Get the object from S3
            obj = self.s3.get_object(Bucket=bucket, Key=file_key)
            
            if file_key.endswith('.gz'):
                # Decompress and decode
                with gzip.GzipFile(fileobj=io.BytesIO(obj['Body'].read())) as f:
                    content = f.read().decode('utf-8')
            else:
                # Just decode
                content = obj['Body'].read().decode('utf-8')
                
            # Process each line as a JSON record
            for line in content.splitlines():
                try:
                    log_entry = json.loads(line.strip())
                    parsed_logs.append(log_entry)
                except json.JSONDecodeError:
                    print(f"Failed to parse line: {line}")
                    continue
                    
        # Extract features
        features_df = self.extract_features(parsed_logs)
        
        return parsed_logs, features_df

    def extract_features(self, logs: List[Dict[str, Any]]) -> pd.DataFrame:
        """
        Extract relevant features from parsed logs
        
        """
        features = []
        
        for log in logs:
            # Extract basic log information
            log_entry = {
                'timestamp': log.get('date'),
                'message': log.get('log'),
                'log_level': None,
                'component': None,
                'action': None,
                'status': None,
                'object_path': None,
                'pod_name': None,
                'namespace': None,
                'host': None,
                'container_name': None,
                'container_image': None
            }
            
            # Extract log level, component and action from message
            if log.get('log'):
                # Example pattern: [2025/04/01 23:59:58] [ info] [output:s3:s3.0] Successfully uploaded object /path/to/object
                log_msg = log.get('log')
                
                # Extract log level
                level_match = re.search(r'\[(info|warn|error|debug)\]', log_msg)
                if level_match:
                    log_entry['log_level'] = level_match.group(1)
                
                # Extract component
                component_match = re.search(r'\[([^:]+):([^:]+):([^\]]+)\]', log_msg)
                if component_match:
                    log_entry['component'] = f"{component_match.group(1)}:{component_match.group(2)}:{component_match.group(3)}"
                
                # Extract action and status
                if "Successfully uploaded" in log_msg:
                    log_entry['action'] = "upload"
                    log_entry['status'] = "success"
                    
                    # Extract object path
                    path_match = re.search(r'object\s+(.+?)(?=-object|\s|$)', log_msg)
                    if path_match:
                        log_entry['object_path'] = path_match.group(1)
            
            # Extract Kubernetes metadata if available
            if 'kubernetes' in log:
                k8s = log.get('kubernetes', {})
                log_entry['pod_name'] = k8s.get('pod_name')
                log_entry['namespace'] = k8s.get('namespace_name')
                log_entry['host'] = k8s.get('host')
                log_entry['container_name'] = k8s.get('container_name')
                log_entry['container_image'] = k8s.get('container_image')
            
            features.append(log_entry)
            
        return pd.DataFrame(features)
    
    def generate_embeddings(self, df: pd.DataFrame, text_column: str = 'message') -> np.ndarray:
        """
        Generate embeddings for log messages
        """
        texts = df[text_column].fillna('').tolist()
        
        # Process in batches to avoid memory issues
        batch_size = 128
        all_embeddings = []
        
        for i in range(0, len(texts), batch_size):
            batch_texts = texts[i:i+batch_size]
            batch_embeddings = self.model.encode(batch_texts)
            all_embeddings.append(batch_embeddings)
            
        # Combine batches
        embeddings = np.vstack(all_embeddings)
        return embeddings
    
    def add_to_index(self, df: pd.DataFrame, embeddings: np.ndarray):
        """
        Add logs and their embeddings to the index

        """
        if len(df) != embeddings.shape[0]:
            raise ValueError("Number of logs and embeddings must match")
            
        # Initialize index if not already done
        if self.index is None:
            self.index = faiss.IndexFlatL2(self.vector_dim)
            
        # Store original data
        start_idx = len(self.log_data)
        self.log_data.extend(df.to_dict('records'))
        
        # Add embeddings to FAISS index
        self.index.add(embeddings.astype(np.float32))
        
        print(f"Added {len(df)} logs to index. Total logs: {len(self.log_data)}")
    
    def identify_patterns(self, df: pd.DataFrame, min_group_size: int = 3) -> Dict[str, Any]:
        """
        Identify patterns in logs based on common attributes
        
        Args:
            df: DataFrame containing logs
            min_group_size: Minimum number of logs to consider a pattern
            
        Returns:
            Dictionary of identified patterns
        """
        patterns = {}
        
        # Group by component and action
        component_groups = df.groupby(['component', 'action']).size()
        significant_components = component_groups[component_groups >= min_group_size].reset_index()
        
        for _, row in significant_components.iterrows():
            component, action = row['component'], row['action']
            pattern_key = f"{component}_{action}"
            
            # Get logs for this pattern
            pattern_logs = df[(df['component'] == component) & (df['action'] == action)]
            
            # Calculate time intervals between logs
            if len(pattern_logs) > 1 and 'timestamp' in pattern_logs.columns:
                pattern_logs['timestamp'] = pd.to_datetime(pattern_logs['timestamp'])
                pattern_logs = pattern_logs.sort_values('timestamp')
                pattern_logs['time_diff'] = pattern_logs['timestamp'].diff().dt.total_seconds()
                
                median_interval = pattern_logs['time_diff'].median()
                mean_interval = pattern_logs['time_diff'].mean()
                min_interval = pattern_logs['time_diff'].min()
                max_interval = pattern_logs['time_diff'].max()
                
                patterns[pattern_key] = {
                    'component': component,
                    'action': action,
                    'count': len(pattern_logs),
                    'median_interval_seconds': float(median_interval) if not pd.isna(median_interval) else None,
                    'mean_interval_seconds': float(mean_interval) if not pd.isna(mean_interval) else None,
                    'min_interval_seconds': float(min_interval) if not pd.isna(min_interval) else None,
                    'max_interval_seconds': float(max_interval) if not pd.isna(max_interval) else None,
                    'sample_logs': pattern_logs.head(3).to_dict('records')
                }
        
        return patterns
    
    def save_to_s3(self, s3_output_path: str):
        """
        Save the processor state to S3
        """
        # Parse S3 URI
        parsed_uri = urlparse(s3_output_path)
        bucket = parsed_uri.netloc
        prefix = parsed_uri.path.lstrip('/')
        
        if not prefix.endswith('/'):
            prefix += '/'
        
        # Serialize the index
        faiss_buffer = io.BytesIO()
        faiss.write_index(self.index, faiss_buffer)
        faiss_buffer.seek(0)
        
        # Save FAISS index to S3
        self.s3.upload_fileobj(
            faiss_buffer,
            bucket,
            f"{prefix}log_index.faiss"
        )
        
        # Serialize and save log data
        log_data_buffer = io.BytesIO()
        pickle.dump(self.log_data, log_data_buffer)
        log_data_buffer.seek(0)
        
        self.s3.upload_fileobj(
            log_data_buffer,
            bucket,
            f"{prefix}log_data.pkl"
        )
        
        # Save metadata
        metadata = {
            'model_name': self.model_name,
            'vector_dim': self.vector_dim,
            'num_logs': len(self.log_data),
            'created_at': datetime.now().isoformat()
        }
        
        metadata_buffer = io.BytesIO(json.dumps(metadata).encode('utf-8'))
        
        self.s3.upload_fileobj(
            metadata_buffer,
            bucket,
            f"{prefix}metadata.json"
        )
        
        print(f"Saved processor state to s3://{bucket}/{prefix}")
    
    def load_from_s3(self, s3_path: str):
        """
        Load the processor state from S3
        """
        # Parse S3 URI
        parsed_uri = urlparse(s3_path)
        bucket = parsed_uri.netloc
        prefix = parsed_uri.path.lstrip('/')
        
        if not prefix.endswith('/'):
            prefix += '/'
        
        # Load FAISS index
        faiss_buffer = io.BytesIO()
        self.s3.download_fileobj(bucket, f"{prefix}log_index.faiss", faiss_buffer)
        faiss_buffer.seek(0)
        self.index = faiss.read_index(faiss_buffer)
        
        # Load log data
        log_data_buffer = io.BytesIO()
        self.s3.download_fileobj(bucket, f"{prefix}log_data.pkl", log_data_buffer)
        log_data_buffer.seek(0)
        self.log_data = pickle.load(log_data_buffer)
        
        print(f"Loaded processor state from s3://{bucket}/{prefix} with {len(self.log_data)} logs")
    
    def create_feature_dynamic_frame(self, df: pd.DataFrame) -> DynamicFrame:
        """
        Convert pandas DataFrame to Glue DynamicFrame for output
        """
        # Convert pandas DataFrame to Spark DataFrame
        spark_df = self.spark.createDataFrame(df)
        
        # Convert to DynamicFrame
        dynamic_frame = DynamicFrame.fromDF(spark_df, self.glue_context, "features")
        
        return dynamic_frame
    
    def save_patterns_to_s3(self, patterns: Dict[str, Any], s3_output_path: str):
        """
        Save identified patterns to S3
        """
        # Parse S3 URI
        parsed_uri = urlparse(s3_output_path)
        bucket = parsed_uri.netloc
        key = parsed_uri.path.lstrip('/')
        
        # Convert to JSON
        patterns_json = json.dumps(patterns, default=str)
        
        # Upload to S3
        self.s3.put_object(
            Body=patterns_json,
            Bucket=bucket,
            Key=key
        )
        
        print(f"Saved patterns to s3://{bucket}/{key}")
    
    def search_similar(self, query: str, k: int = 5) -> List[Dict[str, Any]]:
        """
        Search for logs similar to the query
        """
        if self.index is None or not self.log_data:
            return []
            
        # Generate embedding for query
        query_embedding = self.model.encode([query])[0].reshape(1, -1).astype(np.float32)
        
        # Search index
        distances, indices = self.index.search(query_embedding, k)
        
        # Return results
        results = []
        for i, idx in enumerate(indices[0]):
            if idx < len(self.log_data):  # Ensure index is valid
                result = self.log_data[idx].copy()
                result['similarity_score'] = float(distances[0][i])
                results.append(result)
                
        return results


# Main function for AWS Glue job
def process_logs_glue_job():
    # Parse job arguments
    args = getResolvedOptions(sys.argv, [
        'JOB_NAME',
        's3_input_path',
        's3_output_path',
        's3_model_path',
        'save_model'
    ])
    
    # Initialize Glue context
    sc = SparkContext()
    glue_context = GlueContext(sc)
    spark = glue_context.spark_session
    job = Job(glue_context)
    job.init(args['JOB_NAME'], args)
    
    # Get S3 paths
    s3_input_path = args['s3_input_path']
    s3_output_path = args['s3_output_path']
    s3_model_path = args.get('s3_model_path', None)
    save_model = args.get('save_model', 'true').lower() == 'true'
    
    # Initialize processor
    processor = GlueLogProcessor(
        glue_context=glue_context,
        s3_model_path=s3_model_path
    )
    
    # Process logs
    logs, features_df = processor.parse_logs_from_s3(s3_input_path)
    
    # Generate embeddings
    print(f"Generating embeddings for {len(features_df)} logs")
    embeddings = processor.generate_embeddings(features_df)
    
    # Add to index
    processor.add_to_index(features_df, embeddings)
    
    # Identify patterns
    patterns = processor.identify_patterns(features_df)
    
    # Save output
    # Convert to DynamicFrame and write features
    features_dyf = processor.create_feature_dynamic_frame(features_df)
    glue_context.write_dynamic_frame.from_options(
        frame=features_dyf,
        connection_type="s3",
        connection_options={"path": f"{s3_output_path}/features"},
        format="parquet"
    )
    
    #  Save patterns
    processor.save_patterns_to_s3(patterns, f"{s3_output_path}/patterns/patterns.json")
    
    # Save model if requested
    if save_model:
        model_output_path = f"{s3_output_path}/model"
        processor.save_to_s3(model_output_path)
    
    # Log completion
    print(f"Processed {len(logs)} logs, identified {len(patterns)} patterns")
    print(f"Output written to {s3_output_path}")
    
    # Commit the job
    job.commit()


# Entry point for Glue job
if __name__ == "__main__":
    process_logs_glue_job()