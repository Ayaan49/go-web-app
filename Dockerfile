# Dockerfile

# Set the base image to Golang and alias it as "base" for later use.
FROM golang:1.22.5 as base

# Set the working dir as app, all commands will be executed in this directory.
WORKDIR /app

# Copy the go.mod and go.sum files to the working directory
COPY go.mod ./

# This command downloads all the dependencies specified in the `go.mod` file.
RUN go mod download

# Copy the source code to the working directory
COPY . .

# Build the application
RUN go build -o main .

#######################################################
# Reduce the image size using multi-stage builds

# We will use a distroless image to run the application
FROM gcr.io/distroless/base

# Copy the binary from the previous stage to the current working directory
COPY --from=base /app/main .

# Copy the static files from the previous stage to the current working directory
COPY --from=base /app/static ./static

# Expose the port on which the application will run
EXPOSE 8080

# Command to run the application
CMD ["./main"]
