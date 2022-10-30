build:
	GOARCH=amd64 GOOS=linux go build -o main ./cmd/main.go

run: 
	sam local start-api

watch:
	reflex -r '\.go$\' -- sh -c "make build"