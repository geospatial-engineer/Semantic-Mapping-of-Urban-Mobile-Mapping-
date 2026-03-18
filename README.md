Semantic Mapping of Urban Mobile Mapping LiDAR Using Panoramic OCR and Geometric Back-Projection

This repository accompanies the paper on integrating semantic information from panoramic street-level imagery into mobile mapping LiDAR point clouds using OCR, geometric back-projection, and multi-view fusion.

Overview

The framework detects storefront text and business identifiers in equirectangular panoramas, converts OCR bounding boxes into 3D viewing rays, intersects those rays with LiDAR-supported facade geometry, and fuses repeated detections into stable semantic markers inside the point cloud. The output is a searchable semantic layer for urban LiDAR models.
