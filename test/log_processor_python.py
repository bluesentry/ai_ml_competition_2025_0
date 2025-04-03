import json
import gzip
import pandas as pd
import numpy as np
from datetime import datetime
import os
from typing import List, Dict, Any, Optional
import re

# For embedding generation
from sentence_transformers import SentenceTransformer
import torch

# For vector storage
import faiss
import pickle

class LogProcessor:
    def __init__(self, model_name: str = "all-MiniLM-L6-v2", vector_dim: int = 384):
        """
        Initialize the log processor with embedding model and vector storage
        
        Args:
            model_name: The sentence transformer model to use for embeddings
            vector_dim: Dimension of the embedding vectors
        """
        self.model = SentenceTransformer(model_name)
        self.vector_dim = vector_dim
        self.index = faiss.IndexFlatL2(vector_dim)  # L2 distance for similarity
        self.log_data = []  # Store original log entries
        
    def parse_logs(self, file_path: str) -> List[Dict[str, Any]]:
        """
        Parse logs from a file (supports .json, .gz)
        
        Args:
            file_path: Path to the log file
            
        Returns:
            List of parsed log entries
        """
        parsed_logs = []
        
        if file_path.endswith('.gz'):
            opener = gzip.open
        else:
            opener = open
            
        with opener(file_path, 'rt') as f:
            for line in f:
                try:
                    log_entry = json.loads(line.strip())
                    parsed_logs.append(log_entry)
                except json.JSONDecodeError:
                    print(f"Failed to parse line: {line}")
                    continue
                    
        return parsed_logs
    
    def extract_features(self, logs: List[Dict[str, Any]]) -> pd.DataFrame:
        """
        Extract relevant features from parsed logs
        
        Args:
            logs: List of parsed log entries
            
        Returns:
            DataFrame with extracted features
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
        
        Args:
            df: DataFrame containing logs
            text_column: Column containing text to embed
            
        Returns:
            NumPy array of embeddings
        """
        texts = df[text_column].fillna('').tolist()
        embeddings = self.model.encode(texts, show_progress_bar=True)
        return embeddings
    
    def add_to_index(self, df: pd.DataFrame, embeddings: np.ndarray):
        """
        Add logs and their embeddings to the index
        
        Args:
            df: DataFrame containing logs
            embeddings: NumPy array of embeddings
        """
        if len(df) != embeddings.shape[0]:
            raise ValueError("Number of logs and embeddings must match")
            
        # Store original data
        start_idx = len(self.log_data)
        self.log_data.extend(df.to_dict('records'))
        
        # Add embeddings to FAISS index
        self.index.add(embeddings.astype(np.float32))
        
        print(f"Added {len(df)} logs to index. Total logs: {len(self.log_data)}")
        
    def search_similar(self, query: str, k: int = 5) -> List[Dict[str, Any]]:
        """
        Search for logs similar to the query
        
        Args:
            query: Query text
            k: Number of results to return
            
        Returns:
            List of similar log entries with similarity scores
        """
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
    
    def identify_patterns(self, df: pd.DataFrame, min_group_size: int = 3):
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
                    'median_interval_seconds': median_interval,
                    'mean_interval_seconds': mean_interval,
                    'min_interval_seconds': min_interval,
                    'max_interval_seconds': max_interval,
                    'sample_logs': pattern_logs.head(3).to_dict('records')
                }
        
        return patterns
    
    def save(self, directory: str):
        """
        Save the processor state to disk
        
        Args:
            directory: Directory to save files
        """
        os.makedirs(directory, exist_ok=True)
        
        # Save FAISS index
        faiss.write_index(self.index, os.path.join(directory, "log_index.faiss"))
        
        # Save log data
        with open(os.path.join(directory, "log_data.pkl"), "wb") as f:
            pickle.dump(self.log_data, f)
            
        print(f"Saved processor state to {directory}")
    
    def load(self, directory: str):
        """
        Load the processor state from disk
        
        Args:
            directory: Directory containing saved files
        """
        # Load FAISS index
        self.index = faiss.read_index(os.path.join(directory, "log_index.faiss"))
        
        # Load log data
        with open(os.path.join(directory, "mode/log_data.pkl"), "rb") as f:
            self.log_data = pickle.load(f)
            
        print(f"Loaded processor state from {directory} with {len(self.log_data)} logs")


# Example usage
if __name__ == "__main__":
    processor = LogProcessor()
    
    # Parse logs
    logs = processor.parse_logs("logs/58-fluent-bit-qmn54.json.gz-objectoIEGVYxr")
    
    # Extract features
    log_df = processor.extract_features(logs)
    
    # Generate embeddings
    embeddings = processor.generate_embeddings(log_df)
    
    # Add to index
    processor.add_to_index(log_df, embeddings)
    
    # Identify patterns
    patterns = processor.identify_patterns(log_df)
    print(f"Identified {len(patterns)} patterns")
    
    # Example search
    similar_logs = processor.search_similar("upload error s3")
    print("Similar logs to 'upload error s3':")
    for log in similar_logs:
        print(f"- {log['message']} (score: {log['similarity_score']:.2f})")
    
    # Save processor state
    processor.save("./model")