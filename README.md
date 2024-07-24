# DevOpsify the go web application

The main goal of this project is to implement DevOps practices in the Go web application. The project is a simple website written in Golang. It uses the `net/http` package to serve HTTP requests.

DevOps practices include the following:

- Creating Dockerfile (Multi-stage build)
- Containerization
- Continuous Integration (CI)
- Continuous Deployment (CD)

## Cloning the go web application

Clone the [go web application](https://github.com/iam-veeramalla/go-web-app) in your system and navigate to `go-web-app` directory.

## Dockerizing GO application using multistage builds

1. Run the application locally first
     1. Build the go application first
```
     go build -o main
```
          Go binary `main` gets created.

2. Execute the binary
```
     ./main
```
         Go application should start running in the port mentioned.

 3. Dockerize the application now

   ![[multistage_docker.png]]
```
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


```

Commands to build the Docker container:

```bash
docker build -t <Dockerhub-Username>/go-web-app .
```

Command to run the Docker container:

```bash
docker run -p 8080:8080 <Dockerhub-Username>/go-web-app
```

Command to push the Docker container to Docker Hub:

```bash
docker push <Dockerhub-Username>/go-web-app
```

## Running the application inside k8s with TLS protection

Start a kubernetes cluster using any of the cloud providers. I am using AKS.

We will install nginx-ingress controller and Cert-manager for TLS protected site.

### Install Helm

```
curl https://raw.githubusercontent.com/helm/helm/master/scripts/get-helm-3 | bash
```

### Create nginx namespace

```
kubectl create ns ingress-nginx
```

### Install nginx with Helm package manager

1. Add the following Helm ingress-nginx repository to your Helm repos.

```
helm repo add ingress-nginx https://kubernetes.github.io/ingress-nginx
```

2. Update your Helm repositories.

```
helm repo update
```

3.  Install the NGINX Ingress Controller.

```
helm upgrade ing --install ingress-nginx/ingress-nginx \
    --namespace ingress-nginx \
    --set controller.image.repository="registry.k8s.io/ingress-nginx/controller" \
    --set controller.image.tag="v1.10.1" \
    --set-string controller.config.proxy-body-size="50m" \
    --set controller.service.externalTrafficPolicy="Local"
```

4. Access your NodeBalancer’s assigned external IP address.

```
kubectl --namespace ingress-nginx get services -o wide -w ing-ingress-nginx-controller
```

   - Copy the IP address of the `EXTERNAL IP`
   - Use your DNS control panel (I am using Cloudflare) to create this wildcard A record and assign this IP value to that A Record in your domain as shown in this example below.
    `go-web-app.devfun.me A 35.230.26.54`


### Install Cert-manager

   Our users expect to use HTTPS when accessing services within the cluster so it is important that we provide an automated way of ensuring TLS certificates for DNS names used for our services in the cluster. This can be automated using [cert manager](https://github.com/jetstack/cert-manager)

   1. Install the cert-manager

```
kubectl apply -f https://github.com/cert-manager/cert-manager/releases/download/v1.14.3/cert-manager.yaml
```

   2. Create a cluster issuer to represent a certificate authority (CA) capable of generating signed certificates by honoring certificate signing requests.

```
wget https://gist.githubusercontent.com/lvnilesh/b07132d67fdda57f542ea1651fd4e925/raw/9f3ecfede780c17ffd84b5467ea3b86335a9b9c1/cluster-issuer.yaml
```

Edit the issuer with your own credentials.

```
vi cluster-issuer.yaml
```

  Apply this command after editing the file.

```
kubectl apply -f cluster-issuer.yaml
```


   3. Create a secret that contains your CloudFlare API Key

   - Find your global API key from cloudflare and then, in the first line below, replace `9ddc2cdc84d045bdce9b3018da6bb8bc158bc` with your actual key and run this code block in one copy/paste.

```
API_KEY=$(echo -n "9ddc2cdc84d045bdce9b3018da6bb8bc158bc" | base64)
```


```
cat <<EOF | kubectl apply -f -
---
apiVersion: v1
kind: Secret
metadata:
  name: cloudflare-api-key
  namespace: cert-manager
type: Opaque
data:
  api-key: $API_KEY
EOF
```

- Now, we can run services in your cluster and deliver to our users automatically via ingress in a secure fashion thanks to cert manager and letsencrypt.

### Run TLS protected go-web-app in your cluster

Any website that uses HTTPS is called TLS protected. We have already configured the cert-manager to issue TLS certificates to our websites automatically. Now, we will actually deploy a sample WordPress website to see it happen.

Running TLS protected services in your cluster typically involves creating a deployment, mapping a service to that deployment and letting ingress know which DNS name should map to that service you created.

We will carry out the above mentioned steps now:

  -  Create a k8s directory and a manifests directory inside it:
```
mkdir k8s

cd k8s

mkdir manifests

cd manifests
```

1. Create a deployment manifest:

```
apiVersion: apps/v1
kind: Deployment
metadata:
  name: go-web-app
  labels:
    app: go-web-app
spec:
  replicas: 1
  selector:
    matchLabels:
      app: go-web-app
  template:
    metadata:
      labels:
        app: go-web-app
    spec:
      containers:
      - name: go-web-app
        image: <Dockerhub-Username>/go-web-app:v1
        ports:
        - containerPort: 8080
```

2. Create a svc manifest:

```
apiVersion: v1
kind: Service
metadata:
  name: go-web-app
spec:
  ports:
    - port: 80
      targetPort: 8080
  selector:
    app: go-web-app
```

3. Create an inggress manifest:

```
---
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: go-web-app
  annotations:
    # kubernetes.io/ingress.class: nginx
    cert-manager.io/cluster-issuer: letsencrypt-prod
spec:
  ingressClassName: nginx
  rules:
    - host: go-web-app.devfun.me
      http:
        paths:
          - backend:
              service:
                name: go-web-app
                port:
                  number: 80
            path: /
            pathType: Prefix
  tls:
    - hosts:
        - "go-web-app.devfun.me"
      secretName: go-web-app-tls

```
Edit this ingress manifest with your domain detail that would map that DNS name to the service you created earlier.

You can access it by navigating to `http://<your-own-dns-name>/courses` in your web browser.

The site is deployed successfully in k8s using TLS protection!


## Create a helm chart for the application

Helm helps you manage Kubernetes applications — Helm Charts help you define, install, and upgrade even the most complex Kubernetes application.

```
helm create go-web-app-chart
```

 This will create `go-web-app-chart` directory inside the `helm` directory which will consist of the following:

```

go-web-app-chart/
  Chart.yaml
  values.yaml
  charts/
  templates/
  ...
```

3. We will remove all the manifests inside the `templates/` and add our own manifests inside it:

```
rm -rf go-web-app-chart/templates/*

cd go-web-app-chart/templates

cp ../../../k8s/manifests/* .

```

4. We will edit all the manifests according to our needs and update their values in `values.yaml`

- `deployment.yaml`
```
apiVersion: apps/v1
kind: Deployment
metadata:
  name: {{ .Values.appName }}
  labels:
    app: {{ .Values.appName }}
spec:
  replicas: 1
  selector:
    matchLabels:
      app: {{ .Values.appName }}
  template:
    metadata:
      labels:
        app: {{ .Values.appName }}
    spec:
      containers:
      - name: {{ .Values.appName }}
        image: "{{ .Values.image.name }}:{{ .Values.image.tag }}"
        ports:
        - containerPort: 8080
```

-  `service,yaml`
```
apiVersion: v1
kind: Service
metadata:
  name: {{ .Values.appName }}
spec:
  ports:
    - port: 80
      targetPort: 8080
  selector:
    app: {{ .Values.appName }}

```

- `ing.yaml`
```
---
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: {{ .Values.appName }}
  annotations:
    # kubernetes.io/ingress.class: nginx
    cert-manager.io/cluster-issuer: letsencrypt-prod
spec:
  ingressClassName: nginx
  rules:
    - host: go-web-app.devfun.me
      http:
        paths:
          - backend:
              service:
                name: {{ .Values.appName }}
                port:
                  number: 80
            path: /
            pathType: Prefix
  tls:
    - hosts:
        - "go-web-app.devfun.me"
      secretName: go-web-app-tls

```

5. Updating `values.yaml`

```
appName: go-web-app

image:
  name: ayaan49/go-web-app
  tag: v1

```

6. Now we will delete all our previous kubernetes objects and install all of it with helm instead:

```
kubectl delete deployment go-web-app

kubectl delete service go-web-app

kubectl delete ing go-web-app
```

7. Now let's navigate to helm directory and install the application with helm

```
helm install go-web-app ./go-web-app-chart
```

Access the site on `http://<your-own-dns-name>/courses`

8. We can also uninstall our application using:

```
helm uninstall go-web-app
```

## Creating CI/CD pipeline

### 1. Continuous Integration using Github Actions:

Continuous Integration (CI) is the practice of automating the integration of code changes into a shared repository. CI helps to catch bugs early in the development process and ensures that the code is always in a deployable state.

We will use GitHub Actions to implement CI for the Go web application. GitHub Actions is a feature of GitHub that allows you to automate workflows, such as building, testing, and deploying code.

The GitHub Actions workflow will run the following steps:

- Checkout the code from the repository
- Build the Docker image
- Run the Docker container
- Run tests

1. First push your go-web-app in a github repo:

```
git init

git add .

git commit -m "Initial commit"

git push -u origin main

```

Make sure to remove the previous `.git` folder from your project before `git init`.

2. Inside the repo create `.github/workflows` folder:

```
mkdir .github

cd .github

mkdir workflows
```

3. Create a file called `cicd.yaml` inside the `workflows` and add the following code:

```
# CICD using GitHub actions

name: CI/CD

# Exclude the workflow to run on changes to the helm chart
on:
  push:
    branches:
      - main
    paths-ignore:
      - 'helm/**'
      - 'k8s/**'
      - 'README.md'

jobs:

  build:
    runs-on: ubuntu-latest

    steps:
    - name: Checkout repository
      uses: actions/checkout@v4

    - name: Set up Go 1.22
      uses: actions/setup-go@v2
      with:
        go-version: 1.22

    - name: Build
      run: go build -o go-web-app

    - name: Test
      run: go test ./...


  code-quality:
    runs-on: ubuntu-latest

    steps:
    - name: Checkout repository
      uses: actions/checkout@v4

    - name: Run golangci-lint
      uses: golangci/golangci-lint-action@v6
      with:
        version: v1.56.2


  push:
    runs-on: ubuntu-latest

    needs: build

    steps:
    - name: Checkout repository
      uses: actions/checkout@v4

    - name: Set up Docker Buildx
      uses: docker/setup-buildx-action@v1

    - name: Login to DockerHub
      uses: docker/login-action@v3
      with:
        username: ${{ secrets.DOCKERHUB_USERNAME }}
        password: ${{ secrets.DOCKERHUB_TOKEN }}

    - name: Build and Push action
      uses: docker/build-push-action@v6
      with:
        context: .
        file: ./Dockerfile
        push: true
        tags: ${{ secrets.DOCKERHUB_USERNAME }}/go-web-app:${{github.run_id}}


  update-newtag-in-helm-chart:
    runs-on: ubuntu-latest

    needs: push

    steps:
    - name: Checkout repository
      uses: actions/checkout@v4
      with:
        token: ${{ secrets.TOKEN }}

    - name: Update tag in Helm chart
      run: |
        sed -i 's/tag: .*/tag: "${{github.run_id}}"/' helm/go-web-app-chart/values.yaml

    - name: Commit and push changes
      run: |
        git config --global user.email "<your-github-email>"
        git config --global user.name "<your-github-username>"
        git add helm/go-web-app-chart/values.yaml
        git commit -m "Update tag in Helm chart"
        git push
```

This is the github actions code used for continuous integration of the project.

4. Navigate to the settings of your `go-web-app` repo.
5. Click on `Secrets and variables` and select `Actions`
6. Create three `New Repository Secret`and the following secrets:

```
# Your Dockerhub Username
DOCKERHUB_USERNAME

# Your Dockerhub Personal Access Token which you can generate in your Dockerhub account
DOCKERHUB_TOKEN

# Your Github Personal Aceess Token which you can generate in your Github account
TOKEN
```

We create these three secrets so that we don't leak our passwords in the CICD manifest.

7. Push these changes in your repo and you have automated your project.
8. Now a new docker image with `github.run_id` will be pushed into your Dockerhub account when it passes all the stages in Github actions.

### 2. Continuous Deployment using ArgoCD

Continuous Deployment (CD) is the practice of automatically deploying code changes to a production environment. CD helps to reduce the time between code changes and deployment, allowing you to deliver new features and fixes to users faster.

We will use Argo CD to implement CD for the Go web application. Argo CD is a declarative, GitOps continuous delivery tool for Kubernetes. It allows you to deploy applications to Kubernetes clusters using Git as the source of truth.

The Argo CD application will deploy the Go web application to a Kubernetes cluster. The application will be automatically synced with the Git repository, ensuring that the application is always up to date.

1. Install ArgoCD in your cluster:

```
kubectl create namespace argocd
kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml
```

2. Access the ArgoCD UI (Loadbalancer service):

```
kubectl patch svc argocd-server -n argocd -p '{"spec": {"type": "LoadBalancer"}}'
```

3. Get the Loadbalancer service IP:

```
kubectl get svc argocd-server -n argocd
```

Copy the external IP and paste it on your browser and you will be greeted with the ArgoCD login page.

4. Set the username as:

```
admin
```

5. And get the password like this:

```
# You will see argocd-initial-admin-secret
kubectl get secrets -n argocd

# Edit the secret to copy the password
kubectl edit secrets argocd-initial-admin-secret -n argocd

# Decode the copied password
echo -n ODkycklXaDFESjRLcGlodA== | base64 --decode

```

Copy the decoded password without the `%` symbol and paste it in the ArgoCD login page to login.

6. Click on `New App` and add the following:

```
# Application Name
go-web-app

# Project Name
default

# Sync Policy
Automatic

# Repository URL
<your github project URL>

# Path
Select the automatically detected path

# Cluster URL
Select the automatically detected URL

# Namespace
Default

```

After completing the above step click on `CREATE` and your CICD pipeline is ready!


![[argocd_dashboard.png]]

![[argo3.png]]

The site should look like this on the browser:

![[golang-website.png]]
