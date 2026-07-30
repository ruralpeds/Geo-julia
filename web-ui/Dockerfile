# Build stage
FROM node:18-alpine AS builder

WORKDIR /app

# Copy package files
COPY web-ui/package*.json ./

# Install dependencies
RUN npm ci --legacy-peer-deps

# Copy source code
COPY web-ui/src ./src
COPY web-ui/index.html ./
COPY web-ui/vite.config.js ./
COPY web-ui/tailwind.config.js ./
COPY web-ui/postcss.config.js ./

# Build the application
RUN npm run build

# Production stage
FROM nginx:alpine

# Copy nginx configuration
COPY web-ui/nginx.conf /etc/nginx/nginx.conf

# Copy built application from builder
COPY --from=builder /app/dist /usr/share/nginx/html

# Expose port
EXPOSE 80

# Health check
HEALTHCHECK --interval=30s --timeout=3s --start-period=5s --retries=3 \
  CMD wget --quiet --tries=1 --spider http://localhost/health || exit 1

# Start nginx
CMD ["nginx", "-g", "daemon off;"]
