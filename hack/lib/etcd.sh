#!/usr/bin/env bash
#https://github.com/kubernetes-sigs/scheduler-plugins/blob/master/hack/lib/etcd.sh

# A set of helpers for starting/running etcd for tests

ETCD_VERSION=${ETCD_VERSION:-3.4.9}
ETCD_HOST=${ETCD_HOST:-127.0.0.1}
ETCD_PORT=${ETCD_PORT:-2379}
export KUBE_INTEGRATION_ETCD_URL="http://${ETCD_HOST}:${ETCD_PORT}"

kube::etcd::validate() {
  # validate if in path
  command -v etcd >/dev/null || {
    kube::log::usage "etcd must be in your PATH"
    kube::log::info "You can use 'hack/install-etcd.sh' to install a copy in third_party/."
    exit 1
  }

  # validate if etcd is running and $ETCD_PORT is in use
  if ps -ef | grep "etcd " | grep ${ETCD_PORT} &> /dev/null; then
    kube::log::usage "unable to start etcd as port ${ETCD_PORT} is in use. please stop the process listening on this port and retry."
    exit 1
  fi

  # need set the env of "ETCD_UNSUPPORTED_ARCH" on unstable arch.
  arch=$(uname -m)
  if [[ $arch =~ aarch* ]]; then
	  export ETCD_UNSUPPORTED_ARCH=arm64
  elif [[ $arch =~ arm* ]]; then
	  export ETCD_UNSUPPORTED_ARCH=arm
  fi
  # validate installed version is at least equal to minimum
  version=$(etcd --version | grep Version | head -n 1 | cut -d " " -f 3)
  if [[ $(kube::etcd::version "${ETCD_VERSION}") -gt $(kube::etcd::version "${version}") ]]; then
    kube::log::usage "etcd version ${ETCD_VERSION} or greater required."
    kube::log::info "You can use 'hack/install-etcd.sh' to install."
    exit 1
  fi
}

kube::etcd::version() {
  printf '%s\n' "${@}" | awk -F . '{ printf("%d%03d%03d\n", $1, $2, $3) }'
}

kube::etcd::start() {
  # validate before running
  kube::etcd::validate

  # Start etcd
  ETCD_DIR=${ETCD_DIR:-$(mktemp -d 2>/dev/null || mktemp -d -t test-etcd.XXXXXX)}
  if [[ -d "${ARTIFACTS:-}" ]]; then
    ETCD_LOGFILE="${ARTIFACTS}/etcd.$(uname -n).$(id -un).log.DEBUG.$(date +%Y%m%d-%H%M%S).$$"
  else
    ETCD_LOGFILE=${ETCD_LOGFILE:-"/dev/null"}
  fi
  kube::log::info "etcd --advertise-client-urls ${KUBE_INTEGRATION_ETCD_URL} --data-dir ${ETCD_DIR} --listen-client-urls http://${ETCD_HOST}:${ETCD_PORT} --debug > \"${ETCD_LOGFILE}\" 2>/dev/null"
  etcd --advertise-client-urls "${KUBE_INTEGRATION_ETCD_URL}" --data-dir "${ETCD_DIR}" --listen-client-urls "${KUBE_INTEGRATION_ETCD_URL}" --debug 2> "${ETCD_LOGFILE}" >/dev/null &
  ETCD_PID=$!

  echo "Waiting for etcd to come up."
  kube::util::wait_for_url "${KUBE_INTEGRATION_ETCD_URL}/health" "etcd: " 0.25 80
  curl -fs -X POST "${KUBE_INTEGRATION_ETCD_URL}/v3/kv/put" -d '{"key": "X3Rlc3Q=", "value": ""}'
}

kube::etcd::stop() {
  if [[ -n "${ETCD_PID-}" ]]; then
    kill "${ETCD_PID}" &>/dev/null || :
    wait "${ETCD_PID}" &>/dev/null || :
  fi
}

kube::etcd::clean_etcd_dir() {
  if [[ -n "${ETCD_DIR-}" ]]; then
    rm -rf "${ETCD_DIR}"
  fi
}

kube::etcd::cleanup() {
  kube::etcd::stop
  kube::etcd::clean_etcd_dir
}

kube::etcd::install() {
  (
    local os
    local arch

    os=$(kube::util::host_os)
    arch=$(kube::util::host_arch)

    if [[ $(readlink etcd) == etcd-v${ETCD_VERSION}-${os}-* ]]; then
      kube::log::info "etcd v${ETCD_VERSION} already installed. To use:"
      kube::log::info "export PATH=\"$(pwd)/etcd:\${PATH}\""
      return  #already installed
    fi

    if [[ ${os} == "darwin" ]]; then
      download_file="etcd-v${ETCD_VERSION}-darwin-amd64.zip"
      url="https://github.com/etcd-io/etcd/releases/download/v${ETCD_VERSION}/${download_file}"
      kube::util::download_file "${url}" "${download_file}"
      unzip -o "${download_file}"
      ln -fns "etcd-v${ETCD_VERSION}-darwin-amd64" etcd
      rm "${download_file}"
    else
      url="https://github.com/etcd-io/etcd/releases/download/v${ETCD_VERSION}/etcd-v${ETCD_VERSION}-linux-${arch}.tar.gz"
      download_file="etcd-v${ETCD_VERSION}-linux-${arch}.tar.gz"
      kube::util::download_file "${url}" "${download_file}"
      tar xzf "${download_file}"
      ln -fns "etcd-v${ETCD_VERSION}-linux-${arch}" etcd
      rm "${download_file}"
    fi
    kube::log::info "etcd v${ETCD_VERSION} installed. To use:"
    kube::log::info "export PATH=\"$(pwd)/etcd:\${PATH}\""
  )
}
