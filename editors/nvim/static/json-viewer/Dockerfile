FROM node:24-alpine AS base
RUN npm install -g pnpm@10.10.0

FROM base AS source
WORKDIR /app
RUN apk add --no-cache git
RUN git clone --depth 1 https://github.com/AykutSarac/jsoncrack.com.git .

FROM base AS deps
WORKDIR /app
COPY --from=source /app/package.json /app/pnpm-lock.yaml ./
RUN corepack enable pnpm && pnpm install --frozen-lockfile

FROM base AS builder
WORKDIR /app
COPY --from=deps /app/node_modules ./node_modules
COPY --from=source /app .
ENV NEXT_PUBLIC_NODE_LIMIT=50000
RUN corepack enable pnpm && pnpm run build

FROM nginxinc/nginx-unprivileged:stable
WORKDIR /app
COPY --from=builder /app/out /app
COPY --from=source /app/nginx.conf /etc/nginx/conf.d/default.conf
