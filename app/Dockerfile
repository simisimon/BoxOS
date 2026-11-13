FROM ghcr.io/cirruslabs/flutter:stable AS build

WORKDIR /app
COPY app/ ./

RUN flutter pub get

ARG APP_ENV=production
ARG API_BASE_URL=http://localhost:8080
ARG AUTH_REDIRECT_URL=http://localhost:3000/auth/callback
# true hides sign-up and password reset (invite-only production).
ARG INVITE_ONLY=false

# --no-web-resources-cdn serves CanvasKit from this server, not Google's CDN.
RUN flutter build web --release --no-web-resources-cdn \
    --dart-define=ENV=${APP_ENV} \
    --dart-define=API_BASE_URL=${API_BASE_URL} \
    --dart-define=AUTH_REDIRECT_URL=${AUTH_REDIRECT_URL} \
    --dart-define=INVITE_ONLY=${INVITE_ONLY}

# Roboto and the fallback fonts (symbols, emoji) come from this server, not
# fonts.gstatic.com: point the engine at font-fallback/ and mirror the files
# it names there. CJK is left out (~560 files); those characters show as boxes.
# Only here, so the dev server keeps Flutter's default.
RUN grep -q '_flutter.loader.load({' build/web/flutter_bootstrap.js && \
    sed -i 's|_flutter.loader.load({|_flutter.loader.load({ config: { fontFallbackBaseUrl: "font-fallback/" },|' \
      build/web/flutter_bootstrap.js && \
    mkdir -p build/web/font-fallback && cd build/web/font-fallback && \
    grep -oE '[a-z0-9]+/v[0-9]+/[A-Za-z0-9_.-]+\.(woff2|ttf)' ../main.dart.js | sort -u \
    | grep -vE '^notosans(jp|kr|hk|tc|sc)/' > files.txt && \
    test -s files.txt && \
    while read -r f; do \
      mkdir -p "$(dirname "$f")" && \
      curl -fsS --retry 3 -o "$f" "https://fonts.gstatic.com/s/$f" || exit 1; \
    done < files.txt && \
    rm files.txt

FROM nginx:1.27-alpine
COPY app/nginx.conf /etc/nginx/conf.d/default.conf
COPY --from=build /app/build/web /usr/share/nginx/html

EXPOSE 80
