# GeoSpatial Analysis Engine - Web UI

A comprehensive web frontend for the GeoSpatial Analysis Engine REST API.

## Features

- 🔐 **Authentication**: Secure token-based login system
- 📊 **Dashboard**: Real-time server status and job monitoring
- 🔍 **Spatial Analysis**: Interactive interface for all spatial operations
- 🤖 **Machine Learning**: Model training and prediction interface
- 📈 **Visualizations**: Interactive maps, heatmaps, and 3D plots
- 💼 **Job Management**: Submit, monitor, and manage async jobs
- 📥 **Data Ingestion**: Support for NOAA, USGS, OSM, and Copernicus data
- 📤 **Export**: Download results as JSON, GeoJSON, and GeoTIFF

## Architecture

```
web-ui/
├── src/
│   ├── components/          # Reusable Vue components
│   │   ├── IngestModal.vue
│   │   ├── AnalysisModal.vue
│   │   └── VisualizationModal.vue
│   ├── views/               # Page components
│   │   ├── LoginPage.vue
│   │   ├── DashboardPage.vue
│   │   ├── AnalysisPage.vue
│   │   └── JobsPage.vue
│   ├── stores/              # Pinia state management
│   │   └── app.js          # Application state
│   ├── api/                 # API client
│   │   └── client.js       # REST API integration
│   ├── App.vue             # Root component
│   └── main.js             # Entry point
├── index.html              # HTML template
├── package.json            # Dependencies
├── vite.config.js          # Build configuration
└── tailwind.config.js      # Styling configuration
```

## Installation

### Prerequisites
- Node.js 16+
- npm or yarn
- GeoSpatial Engine API running (localhost:8080)

### Setup

```bash
# Install dependencies
npm install

# Start development server
npm run dev

# Build for production
npm run build

# Preview production build
npm run preview
```

## Usage

### Login

1. Navigate to `http://localhost:3000`
2. Enter credentials:
   - Username: `admin`
   - Password: `changeme`
3. Click "Login"

### Ingest Data

1. Click "📊 Ingest Data" in sidebar
2. Select data source (NOAA, USGS, OSM, Copernicus)
3. Upload JSON/CSV/GeoJSON file
4. Click "Ingest Data"

### Run Analysis

1. Click "🔍 New Analysis" in sidebar
2. Select operation (Buffer, Hotspot, Cluster, etc.)
3. Configure parameters
4. Click "Run Analysis" (sync) or "Submit as Job" (async)

### Monitor Jobs

1. Navigate to "Jobs" tab
2. View list of all submitted jobs
3. Select job to view details and progress
4. Download results when complete

### Create Visualizations

1. Click "📈 Visualize" in sidebar
2. Select visualization type (Map, Heatmap, 3D, Animation)
3. Choose variable and colormap
4. Click "Generate"

## API Integration

The web UI connects to the GeoSpatial Analysis Engine REST API with the following endpoints:

### Authentication
- `POST /auth/login` - Get authentication token

### Data Management
- `POST /ingest` - Ingest data from sources

### Analysis
- `POST /analyze` - Run synchronous analysis
- `POST /analyze/async` - Submit async job
- `GET /jobs/{id}` - Get job status and results

### Visualization
- `POST /visualize` - Generate visualization
- `POST /export` - Export results

### Utilities
- `GET /health` - Health check
- `GET /status` - Server status

## Configuration

### Environment Variables

Create a `.env` file:

```env
VITE_API_URL=http://localhost:8080
VITE_API_TIMEOUT=30000
```

### Tailwind CSS

Configure in `tailwind.config.js` for custom styling.

## Development

### File Structure

```
src/
├── components/    # Reusable UI components
├── views/         # Page-level components
├── stores/        # Pinia stores (state management)
├── api/           # API client and services
├── App.vue        # Root component
└── main.js        # Application entry point
```

### Adding New Pages

1. Create component in `src/views/`
2. Import in `App.vue`
3. Add navigation in navbar
4. Add route to page selection logic

### Adding New Components

1. Create component in `src/components/`
2. Use `<script setup>` syntax
3. Import and use in pages

### State Management

Use Pinia store for global state:

```javascript
import { useAppStore } from '@/stores/app'

const appStore = useAppStore()
```

## Styling

The UI uses **Tailwind CSS** for styling. All components follow the utility-first approach.

Custom styles can be added in component `<style scoped>` blocks.

## Performance

- **Code Splitting**: Automatic with Vite
- **Lazy Loading**: Views load on demand
- **Caching**: HTTP responses cached in browser
- **Compression**: Production build optimized and minified

## Security

- **Token Storage**: Tokens stored in localStorage
- **HTTPS**: Recommended for production
- **CORS**: Configured in API server
- **Rate Limiting**: Enforced on API side

## Deployment

### Docker

```bash
# Build image
docker build -f Dockerfile.ui -t geospatial-web-ui:1.0.0 .

# Run container
docker run -p 3000:80 geospatial-web-ui:1.0.0
```

### Production Build

```bash
# Build for production
npm run build

# Serve dist/ directory with static server (Nginx, Apache, etc.)
```

## Troubleshooting

### API Connection Issues

- Verify API is running on `localhost:8080`
- Check browser console for CORS errors
- Ensure correct API URL in `.env`

### Build Issues

- Delete `node_modules/` and `dist/`
- Run `npm install` again
- Clear npm cache: `npm cache clean --force`

### Login Issues

- Verify credentials (admin/changeme)
- Check API `/auth/login` endpoint
- Clear browser localStorage

## Contributing

1. Create feature branch
2. Make changes following existing patterns
3. Test thoroughly
4. Submit pull request

## License

MIT License - See LICENSE file

## Support

- Issues: https://github.com/timothyhartzog/Geo-julia/issues
- Documentation: See API_DOCUMENTATION.md
- API Server: See DEPLOYMENT_GUIDE.md

---

**Version**: 1.0.0  
**Last Updated**: April 13, 2026  
**Status**: Production Ready
