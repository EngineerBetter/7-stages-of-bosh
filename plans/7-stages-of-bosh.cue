package seven_stages_of_bosh

import (
    "alpha.dagger.io/dagger"
    "alpha.dagger.io/docker"
    "alpha.dagger.io/os"
    "alpha.dagger.io/http"
)

source: dagger.#Artifact & dagger.#Input
space: string & dagger.#Input
manifest: string & dagger.#Input
google_credentials: dagger.#Secret & dagger.#Input
url: string & dagger.#Input

login: os.#Container & {
    image: docker.#Pull & {
        from: "gcr.io/google.com/cloudsdktool/cloud-sdk:alpine"
    }
    env: CLUSTER: string & dagger.#Input
    secret: "/kube/google_application_credentials.json": google_credentials
    command: """
        set -euo pipefail
        project_id="$(python3 -c 'import json, os, pathlib; print(json.loads(pathlib.Path("/kube/google_application_credentials.json").read_text())["project_id"])')"
        gcloud auth activate-service-account --key-file=/kube/google_application_credentials.json --project="$project_id"
        region="${REGION:-$(gcloud container clusters list --filter "name=$CLUSTER" --format='value(location)')}"
        cat > /kube/config <<EOF
        apiVersion: v1
        kind: Config
        current-context: default
        contexts: [{name: default, context: {cluster: default, user: gcp}}]
        users: [{name: gcp, user: {auth-provider: {name: gcp}}}]
        clusters:
        - name: default
          cluster:
            server: "https://$(gcloud container clusters describe "${CLUSTER}" --region "${region}" --format='value(endpoint)')"
            certificate-authority-data: "$(gcloud container clusters describe "${CLUSTER}" --region "${region}" --format='value(masterAuth.clusterCaCertificate)')"
        EOF
        """
}

push: os.#Container & {
    image: docker.#Pull & {
        from: "gcr.io/kf-releases/kf-release-deployer:v2.7.0"
    }
    env: URL: url

    mount: "/app": from: source
    dir:     "/app"

    copy: "/creds": from: login
    env: KUBECONFIG: "/creds/kube/config"

    secret: "/kube/google_application_credentials.json": google_credentials
    env: GOOGLE_APPLICATION_CREDENTIALS: "/kube/google_application_credentials.json"

    command: "kf push --space \(space) --manifest \(manifest)"
}

wait: http.#Wait & {
    url: push.env.URL
}
