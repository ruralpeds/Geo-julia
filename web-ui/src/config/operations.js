/**
 * Spatial Operations Configuration
 * Defines all available operations, their parameters, and schemas for form generation
 */

export const OPERATIONS = {
  // Spatial Operations
  buffer: {
    id: 'buffer',
    name: 'Buffer',
    category: 'spatial',
    description: 'Create buffer zones around features',
    icon: '⭕',
    params: [
      {
        name: 'distance',
        label: 'Buffer Distance',
        type: 'number',
        required: true,
        default: 100,
        min: 0,
        max: 10000,
        step: 10,
        unit: 'meters',
        help: 'Distance to buffer from feature edges'
      },
      {
        name: 'units',
        label: 'Units',
        type: 'select',
        required: true,
        default: 'meters',
        options: ['meters', 'kilometers', 'feet', 'miles'],
        help: 'Unit of measurement for buffer distance'
      }
    ]
  },

  intersect: {
    id: 'intersect',
    name: 'Intersect',
    category: 'spatial',
    description: 'Find overlapping features between datasets',
    icon: '✖️',
    params: [
      {
        name: 'overlay_layer',
        label: 'Overlay Layer',
        type: 'select',
        required: true,
        options: [], // Populated from available datasets
        help: 'Second dataset to intersect with'
      },
      {
        name: 'keep_attributes',
        label: 'Keep All Attributes',
        type: 'checkbox',
        required: false,
        default: true,
        help: 'Preserve attributes from both layers'
      }
    ]
  },

  clip: {
    id: 'clip',
    name: 'Clip',
    category: 'spatial',
    description: 'Extract features within bounds',
    icon: '📍',
    params: [
      {
        name: 'bounds',
        label: 'Clipping Bounds',
        type: 'text',
        required: true,
        placeholder: 'WKT or GeoJSON',
        help: 'Boundary polygon to clip features (WKT format)'
      },
      {
        name: 'crs',
        label: 'Coordinate System',
        type: 'select',
        required: false,
        default: 'EPSG:4326',
        options: ['EPSG:4326', 'EPSG:3857', 'EPSG:2154'],
        help: 'Coordinate reference system'
      }
    ]
  },

  dissolve: {
    id: 'dissolve',
    name: 'Dissolve',
    category: 'spatial',
    description: 'Aggregate features by attribute',
    icon: '🔀',
    params: [
      {
        name: 'dissolve_by',
        label: 'Dissolve By',
        type: 'select',
        required: true,
        options: [], // Populated from dataset columns
        help: 'Column to group and dissolve by'
      },
      {
        name: 'aggregation',
        label: 'Aggregation Method',
        type: 'select',
        required: true,
        default: 'first',
        options: ['first', 'last', 'sum', 'mean', 'max', 'min'],
        help: 'How to aggregate attributes'
      }
    ]
  },

  hotspot_analysis: {
    id: 'hotspot_analysis',
    name: 'Hotspot Analysis',
    category: 'statistical',
    description: 'Identify spatial clusters of high values',
    icon: '🔥',
    params: [
      {
        name: 'variable',
        label: 'Analysis Variable',
        type: 'select',
        required: true,
        options: [], // Populated from dataset columns
        help: 'Numeric column to analyze'
      },
      {
        name: 'bandwidth',
        label: 'Bandwidth',
        type: 'number',
        required: false,
        default: 1.0,
        min: 0.1,
        max: 10,
        step: 0.1,
        help: 'Kernel bandwidth for density estimation'
      },
      {
        name: 'threshold',
        label: 'Threshold',
        type: 'number',
        required: false,
        default: 0.5,
        min: 0,
        max: 1,
        step: 0.05,
        help: 'Percentile threshold for hotspot detection'
      }
    ]
  },

  cluster_analysis: {
    id: 'cluster_analysis',
    name: 'Cluster Analysis',
    category: 'statistical',
    description: 'Group features into spatial clusters',
    icon: '📊',
    params: [
      {
        name: 'n_clusters',
        label: 'Number of Clusters',
        type: 'number',
        required: true,
        default: 5,
        min: 2,
        max: 50,
        step: 1,
        help: 'Target number of clusters'
      },
      {
        name: 'method',
        label: 'Clustering Method',
        type: 'select',
        required: true,
        default: 'kmeans',
        options: ['kmeans', 'hierarchical', 'dbscan'],
        help: 'Clustering algorithm to use'
      },
      {
        name: 'variables',
        label: 'Variables to Use',
        type: 'multi-select',
        required: true,
        options: [], // Populated from dataset columns
        help: 'Columns to include in clustering'
      }
    ]
  },

  kriging_interpolation: {
    id: 'kriging_interpolation',
    name: 'Kriging Interpolation',
    category: 'interpolation',
    description: 'Spatial interpolation using kriging',
    icon: '〰️',
    params: [
      {
        name: 'variable',
        label: 'Variable to Interpolate',
        type: 'select',
        required: true,
        options: [], // Populated from dataset columns
        help: 'Numeric column to interpolate'
      },
      {
        name: 'resolution',
        label: 'Grid Resolution',
        type: 'number',
        required: false,
        default: 0.01,
        min: 0.001,
        max: 1,
        step: 0.001,
        help: 'Output grid resolution (degrees)'
      },
      {
        name: 'method',
        label: 'Kriging Method',
        type: 'select',
        required: true,
        default: 'ordinary',
        options: ['ordinary', 'universal', 'co-kriging'],
        help: 'Type of kriging to perform'
      }
    ]
  }
}

export const VISUALIZATION_TYPES = {
  map: {
    id: 'map',
    name: 'Map',
    description: 'Interactive geographic map',
    icon: '🗺️',
    library: 'leaflet',
    params: [
      {
        name: 'colormap',
        label: 'Color Scheme',
        type: 'select',
        default: 'viridis',
        options: ['viridis', 'plasma', 'YlOrRd', 'RdYlBu', 'Blues', 'Greens']
      },
      {
        name: 'opacity',
        label: 'Layer Opacity',
        type: 'range',
        default: 0.7,
        min: 0,
        max: 1,
        step: 0.1
      }
    ]
  },

  heatmap: {
    id: 'heatmap',
    name: 'Heatmap',
    description: 'Density heatmap visualization',
    icon: '🔥',
    library: 'leaflet',
    params: [
      {
        name: 'radius',
        label: 'Radius',
        type: 'number',
        default: 25,
        min: 5,
        max: 100
      },
      {
        name: 'colormap',
        label: 'Color Scheme',
        type: 'select',
        default: 'YlOrRd',
        options: ['YlOrRd', 'YlGn', 'Blues', 'Purples']
      }
    ]
  },

  chart: {
    id: 'chart',
    name: 'Chart',
    description: 'Statistical chart visualization',
    icon: '📈',
    library: 'chartjs',
    params: [
      {
        name: 'chart_type',
        label: 'Chart Type',
        type: 'select',
        default: 'bar',
        options: ['bar', 'line', 'scatter', 'histogram']
      },
      {
        name: 'x_axis',
        label: 'X-Axis Variable',
        type: 'select',
        options: []
      },
      {
        name: 'y_axis',
        label: 'Y-Axis Variable',
        type: 'select',
        options: []
      }
    ]
  },

  '3d': {
    id: '3d',
    name: '3D Plot',
    description: 'Three-dimensional visualization',
    icon: '📐',
    library: 'threejs',
    params: [
      {
        name: 'x_axis',
        label: 'X-Axis',
        type: 'select',
        options: []
      },
      {
        name: 'y_axis',
        label: 'Y-Axis',
        type: 'select',
        options: []
      },
      {
        name: 'z_axis',
        label: 'Z-Axis',
        type: 'select',
        options: []
      }
    ]
  },

  animation: {
    id: 'animation',
    name: 'Animated Map',
    description: 'Time-series animated visualization',
    icon: '🎬',
    library: 'leaflet',
    params: [
      {
        name: 'time_variable',
        label: 'Time Variable',
        type: 'select',
        options: [],
        help: 'Time column for animation'
      },
      {
        name: 'speed',
        label: 'Animation Speed',
        type: 'select',
        default: 'normal',
        options: ['slow', 'normal', 'fast']
      }
    ]
  }
}

export const ML_OPERATIONS = {
  train: {
    id: 'train',
    name: 'Train Model',
    category: 'ml',
    description: 'Train a machine learning model',
    icon: '🤖',
    params: [
      {
        name: 'model_type',
        label: 'Model Type',
        type: 'select',
        required: true,
        default: 'forest',
        options: ['forest', 'ridge', 'lasso', 'linear', 'boost'],
        help: 'Type of model to train'
      },
      {
        name: 'target_variable',
        label: 'Target Variable',
        type: 'select',
        required: true,
        options: [], // Populated from columns
        help: 'Numeric column to predict'
      },
      {
        name: 'features',
        label: 'Features',
        type: 'multi-select',
        required: true,
        options: [], // Populated from columns
        help: 'Columns to use as features'
      },
      {
        name: 'train_fraction',
        label: 'Training Fraction',
        type: 'range',
        required: false,
        default: 0.8,
        min: 0.5,
        max: 0.95,
        step: 0.05,
        help: 'Fraction of data for training (rest for validation)'
      },
      {
        name: 'cross_validation',
        label: 'Cross-Validation Folds',
        type: 'number',
        required: false,
        default: 5,
        min: 2,
        max: 10,
        step: 1,
        help: 'Number of CV folds'
      }
    ]
  },

  predict: {
    id: 'predict',
    name: 'Make Predictions',
    category: 'ml',
    description: 'Generate predictions using trained model',
    icon: '🎯',
    params: [
      {
        name: 'model_id',
        label: 'Trained Model',
        type: 'select',
        required: true,
        options: [], // Populated from trained models
        help: 'Select a previously trained model'
      }
    ]
  }
}

// Operation categories for UI grouping
export const OPERATION_CATEGORIES = {
  spatial: {
    name: 'Spatial Operations',
    description: 'Geometric operations on features',
    icon: '🗺️'
  },
  statistical: {
    name: 'Statistical Analysis',
    description: 'Statistical and pattern analysis',
    icon: '📊'
  },
  interpolation: {
    name: 'Interpolation',
    description: 'Spatial interpolation methods',
    icon: '〰️'
  },
  ml: {
    name: 'Machine Learning',
    description: 'ML model training and prediction',
    icon: '🤖'
  }
}

// Export formats
export const EXPORT_FORMATS = {
  geojson: {
    name: 'GeoJSON',
    description: 'Standard GeoJSON format',
    ext: '.geojson'
  },
  geotiff: {
    name: 'GeoTIFF',
    description: 'GeoTIFF raster format',
    ext: '.tif'
  },
  shp: {
    name: 'Shapefile',
    description: 'ESRI Shapefile format',
    ext: '.zip'
  },
  csv: {
    name: 'CSV',
    description: 'Comma-separated values',
    ext: '.csv'
  },
  json: {
    name: 'JSON',
    description: 'JSON format',
    ext: '.json'
  }
}

// Helper functions
export function getOperation(operationId) {
  return OPERATIONS[operationId] || ML_OPERATIONS[operationId]
}

export function getOperationsByCategory(category) {
  return Object.values(OPERATIONS).filter(op => op.category === category)
}

export function getAllOperations() {
  return { ...OPERATIONS, ...ML_OPERATIONS }
}

export function getVisualizationType(typeId) {
  return VISUALIZATION_TYPES[typeId]
}
