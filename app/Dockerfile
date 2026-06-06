FROM ghcr.io/cirruslabs/flutter:stable AS build

WORKDIR /app
COPY app/ ./

RUN flutter pub get

ARG APP_ENV=production
ARG API_BASE_URL=http://localhost:8080
ARG AUTH_REDIRECT_URL=http://localhost:3000/auth/callback

RUN flutter build web --release \
    --dart-define=ENV=${APP_ENV} \
    --dart-define=API_BASE_URL=${API_BASE_URL} \
    --dart-define=AUTH_REDIRECT_URL=${AUTH_REDIRECT_URL}

FROM nginx:1.27-alpine
COPY app/nginx.conf /etc/nginx/conf.d/default.conf
COPY --from=build /app/build/web /usr/share/nginx/html

EXPOSE 80
