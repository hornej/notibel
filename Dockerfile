FROM golang:1.22-alpine AS build

WORKDIR /src
COPY go.mod go.sum ./
RUN go mod download

COPY cmd ./cmd
COPY internal ./internal
RUN CGO_ENABLED=0 GOOS=linux go build -o /out/notibeld ./cmd/notibeld

FROM alpine:3.20

RUN apk add --no-cache ca-certificates

WORKDIR /app
COPY --from=build /out/notibeld /usr/local/bin/notibeld

VOLUME ["/data", "/secrets"]
EXPOSE 8787

ENTRYPOINT ["/usr/local/bin/notibeld"]
