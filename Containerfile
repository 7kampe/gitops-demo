FROM docker.io/nginx:latest

RUN echo "Hello, World v2.0!" > /usr/share/nginx/html/index.html