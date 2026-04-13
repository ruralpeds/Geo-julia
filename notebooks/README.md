# GeoSpatial Analysis Engine - Example Notebooks

This directory contains comprehensive Jupyter notebooks demonstrating real-world workflows using the GeoSpatial Analysis Engine.

## Notebooks

### 1. Weather Analysis Workflow
**File**: `01_Weather_Analysis_Workflow.ipynb`

Demonstrates analyzing weather data from NOAA sources:
- Data ingestion from weather station networks
- Spatial buffer operations around measurement points
- Hotspot analysis to identify temperature anomalies
- Spatial autocorrelation testing (Moran's I)
- Interactive map visualization
- Results export for downstream processing

**Key Concepts**: Hotspot analysis, spatial statistics, weather data integration

**Use Case**: Regional climate monitoring and extreme weather detection

---

### 2. Urban Planning Analysis
**File**: `02_Urban_Planning_Analysis.ipynb`

Demonstrates analyzing urban infrastructure using OpenStreetMap data:
- OSM building footprint and attribute data ingestion
- K-means clustering to identify development patterns
- Population density heatmap generation
- Machine learning model for growth prediction
- Development recommendations based on analysis

**Key Concepts**: Clustering, density analysis, predictive modeling

**Use Case**: Urban sprawl analysis and infrastructure planning

---

### 3. Climate Modeling with Kriging Interpolation
**File**: `03_Climate_Modeling_Kriging.ipynb`

Demonstrates climate analysis using Copernicus satellite data:
- Satellite temperature and humidity ingestion
- Kriging interpolation for continuous climate surface estimation
- Spatial autocorrelation analysis for climate patterns
- Interpolated climate heatmap visualization
- Forecast model training for climate prediction

**Key Concepts**: Kriging interpolation, satellite data, climate statistics

**Use Case**: Climate pattern mapping and long-term forecasting

---

### 4. Disease Hotspot Detection
**File**: `04_Disease_Hotspot_Detection.ipynb`

Demonstrates epidemiological analysis using public health data:
- Disease case data ingestion from health departments
- Getis-Ord hotspot identification for disease clusters
- Disease incidence rate calculation
- Risk-stratified heatmap generation
- Public health intervention recommendations
- Time-series trend monitoring

**Key Concepts**: Hotspot analysis, epidemiology, risk assessment

**Use Case**: Pandemic response and disease surveillance

---

### 5. ML Model Training Workflow
**File**: `05_ML_Model_Training_Workflow.ipynb`

Demonstrates a complete machine learning workflow:
- Real estate data ingestion
- Spatial feature engineering
- Multiple algorithm training (Linear, Ridge, Random Forest, Gradient Boosting)
- 5-fold cross-validation
- Feature importance analysis
- Production-ready predictions
- Model deployment strategy

**Key Concepts**: Feature engineering, model selection, cross-validation

**Use Case**: Predictive analytics for real estate valuation

---

## How to Use

### Prerequisites
```bash
# Python 3.7+
pip install requests pandas numpy jupyter

# Optional: For enhanced visualization
pip install matplotlib seaborn folium
```

### Running the Notebooks

1. **Start the GeoSpatial Engine**:
   ```bash
   # In another terminal
   cd path/to/Geo-julia
   julia --project="." -e "include(\"src/main.jl\"); run_server()"
   ```

2. **Launch Jupyter**:
   ```bash
   cd notebooks
   jupyter notebook
   ```

3. **Open a notebook** and run cells sequentially
   - Each notebook is self-contained
   - Default API endpoint: `http://localhost:8080`
   - Default credentials: `admin/changeme`

### Expected Output

Each notebook produces:
- ✓ Successful API calls with status messages
- ✓ Processed geospatial data summaries
- ✓ Analysis results with metrics
- ✓ Visualization confirmations
- ✓ Recommendations or predictions
- ✓ Performance metrics where applicable

## Data Sources

Notebooks demonstrate integration with:
- **NOAA**: Weather and climate data
- **OpenStreetMap (OSM)**: Building and street network data
- **Copernicus**: Satellite imagery and environmental data
- **Public Health Departments**: Disease surveillance data
- **Real Estate Databases**: Property and valuation data

## API Endpoints Used

Each notebook demonstrates these core endpoints:
- `POST /auth/login` - Authentication
- `POST /ingest` - Data ingestion
- `POST /analyze` - Spatial analysis operations
- `POST /predict` - ML predictions
- `POST /visualize` - Visualization generation
- `POST /export` - Results export
- `GET /health` - Health checks

## Customization

To adapt notebooks for your data:

1. **Modify source data**:
   - Replace `weather_data`, `osm_data`, etc. with your GeoJSON
   - Update coordinate ranges for your area of interest
   - Adjust feature lists for your variables

2. **Change analysis parameters**:
   - Adjust buffer distances, cluster counts, grid sizes
   - Modify colormap selections
   - Update model parameters

3. **Add custom operations**:
   - Combine multiple analysis types
   - Create analysis chains
   - Add domain-specific metrics

## Example Outputs

### Weather Analysis
```
✓ Data ingested: 3 measurement points
✓ Hotspot analysis completed (2 hotspots)
✓ Moran's I: 0.7234 (high spatial clustering)
✓ Heatmap created
```

### Urban Planning
```
✓ OSM data ingested: 4 buildings
✓ Clustering analysis (3 clusters identified)
✓ Density heatmap created
✓ Growth prediction model trained (accuracy: 0.92)
```

### Climate Modeling
```
✓ Satellite data loaded: 4 measurement points
✓ Kriging interpolation (100 grid points)
✓ Mean interpolation error: 0.3°C
✓ Climate heatmap created
```

### Disease Detection
```
✓ Disease data ingested: 5 locations
✓ Hotspot analysis (2 high-risk areas identified)
✓ Heatmap visualization created
✓ Recommendations generated
```

### ML Workflow
```
✓ Training data loaded: 4 properties
✓ Features engineered: 4 new variables
✓ Models trained: 4 algorithms
✓ Best model: Random Forest (R²: 0.888)
✓ Cross-validation: Stable (±0.008)
✓ Predictions: Ready for 3 new properties
```

## Troubleshooting

### API Connection Issues
- Verify Engine is running: `curl http://localhost:8080/health`
- Check network connectivity
- Verify correct base URL in notebook

### Data Ingestion Errors
- Validate GeoJSON format using online validators
- Check coordinate ranges (longitude -180 to 180, latitude -90 to 90)
- Ensure feature properties match expected schema

### Analysis Failures
- Verify sufficient data points for analysis
- Check parameter ranges are reasonable
- Consult API documentation for operation specifics

## Learning Path

**Beginner**: Start with Weather Analysis (simplest workflow)
1. Basic data ingestion
2. Simple spatial operations
3. Standard visualization

**Intermediate**: Urban Planning and Climate Modeling
1. Complex data structures
2. Multiple analysis operations
3. Predictive algorithms

**Advanced**: Disease Detection and ML Workflow
1. Complex statistics
2. Real-time monitoring
3. Production workflows

## Production Deployment

To deploy notebook workflows in production:

1. **Convert to Python scripts**:
   ```bash
   jupyter nbconvert --to script notebook.ipynb
   ```

2. **Create REST wrapper**:
   - Accept inputs via API
   - Execute analysis steps
   - Return results as JSON

3. **Implement monitoring**:
   - Log execution times
   - Track API usage
   - Alert on failures

4. **Schedule execution**:
   - Use cron or APScheduler
   - Run on data update events
   - Trigger from upstream systems

## Contributing

To add new example notebooks:

1. Create comprehensive workflow covering 5+ API calls
2. Include sample data with clear comments
3. Provide detailed explanations and insights
4. Follow naming convention: `NN_Descriptive_Title.ipynb`
5. Include troubleshooting section

## Support

For issues or questions:
- Check API documentation: `API_DOCUMENTATION.md`
- Review backend logs
- Consult example outputs above
- Create GitHub issue with notebook and error details

## License

MIT License - Use freely for educational and commercial purposes

---

**Version**: 1.0.0  
**Last Updated**: April 12, 2026  
**Status**: Production Ready  
**Tested with**: Engine v1.0.0 | Python 3.9 | Jupyter 1.0.0
