### Introduction
GoLang Lambda Project

### Prerequisites
- Go
- AWS SAM (Serverless Application Model)
- Reflex
    - install using `go install github.com/cespare/reflex@latest`
    - make sure to set $PATH with Go, visit: https://go.dev/doc/gopath_code


### Running Project
1. build the executable: `make build`
2. run the api: `make run`
3. use hot reload: `make watch`

### Deployment
1. `terraform init`
2. `terraform plan`
3. `terraform apply`