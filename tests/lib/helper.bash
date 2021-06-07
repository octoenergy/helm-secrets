#!/usr/bin/env bash
is_driver() {
    [ "${HELM_SECRETS_DRIVER}" == "${1}" ]
}

is_coverage() {
    [ -n "${BASHCOV_COMMAND_NAME+x}" ]
}

is_curl_installed() {
    command -v curl >/dev/null
}

_helm_cache() {
    env APPDATA="${HELM_CACHE}/home/" HOME="${HELM_CACHE}/home/" helm "$@"
}

_shasum() {
    # MacOS have shasum, others have sha1sum
    if command -v shasum >/dev/null; then
        shasum "$@"
    else
        sha1sum "$@"
    fi
}

_gpg() {
    # cygwin does not have an alias
    if command -v gpg2 >/dev/null; then
        HOME="${HELM_CACHE}" gpg2 "$@"
    else
        HOME="${HELM_CACHE}" gpg "$@"
    fi
}

_mktemp() {
    if [[ -n "${TMPDIR+x}" && "${TMPDIR}" != "" ]]; then
        TMPDIR="${TMPDIR}" mktemp "$@"
    else
        mktemp "$@"
    fi
}

initiate() {
    {
        # cygwin may not have a home directory
        [ -d "${HOME}" ] && mkdir -p "${HOME}"

        # Windows TMPDIR behavior
        if [[ "$(uname -s)" == CYGWIN* ]]; then
            TMPDIR="$(cygpath -m "${TEMP}")"
        elif [ -n "${W_TEMP+x}" ]; then
            TMPDIR="${W_TEMP}"
        fi

        mkdir -p "${HELM_CACHE}/home"
        if [ ! -d "${HELM_CACHE}/chart" ]; then
            helm create "${HELM_CACHE}/chart"
        fi

        helm_plugin_install "secrets"
        helm_plugin_install "diff"
        helm_plugin_install "git"

        _gpg --batch --import "${TEST_DIR}/assets/gpg/private.gpg"
    } >&2
}

setup() {
    env

    GIT_ROOT="$(git rev-parse --show-toplevel)"
    TEST_DIR="${GIT_ROOT}/tests"
    HELM_SECRETS_DRIVER="${HELM_SECRETS_DRIVER:-"sops"}"
    HELM_CACHE="${TEST_DIR}/.tmp/cache/$(uname)/helm"
    REAL_HOME="${HOME}"

    # https://github.com/bats-core/bats-core/issues/39#issuecomment-377015447
    if [[ "$BATS_TEST_NUMBER" -eq 1 ]]; then
        initiate
    fi

    env | grep tests

    SEED="${RANDOM}"

    TEST_TEMP_DIR="$(_mktemp -d)"
    TEST_TEMP_HOME="$(mktemp -d)"
    HOME="${TEST_TEMP_HOME}"

    # shellcheck disable=SC2034
    XDG_DATA_HOME="${HOME}"
    _HELM_PLUGINS="$(helm env HELM_PLUGINS)"

    # Windows
    # See: https://github.com/helm/helm/blob/b4f8312dbaf479e5f772cd17ae3768c7a7bb3832/pkg/helmpath/lazypath_windows.go#L22
    # See: https://github.com/helm/helm/blob/b4f8312dbaf479e5f772cd17ae3768c7a7bb3832/pkg/helmpath/lazypath_windows.go#L22
    # shellcheck disable=SC2034
    APPDATA="${HOME}"
    #mkdir "${TEST_TEMP_DIR}/chart"

    mkdir -p "$(dirname "${_HELM_PLUGINS}")"
    ln -sf "$(_helm_cache env HELM_PLUGINS)" "${_HELM_PLUGINS}"

    # use cached gpg agent
    ln -sf "${HELM_CACHE}/.gnupg/" "${HOME}/.gnupg"

    # copy .kube from real home
    if [ -d "${REAL_HOME}/.kube" ]; then
        ln -sf "${REAL_HOME}/.kube" "${HOME}/.kube"
    fi

    # copy assets
    cp -r "${TEST_DIR}/assets" "${TEST_TEMP_DIR}/"
    if [[ "$(uname)" == "Darwin" || "$(uname)" == "Linux" ]]; then
        # shellcheck disable=SC2016
        SPECIAL_CHAR_DIR="${TEST_TEMP_DIR}/$(printf '%s' 'a@b§c!d\$e\f(g)h=i^j😀')"
        mkdir "${SPECIAL_CHAR_DIR}"
        cp -r "${TEST_DIR}/assets" "${SPECIAL_CHAR_DIR}/"
    fi

    ln -sf "${TEST_DIR}/assets/values/sops/.sops.yaml" "${TEST_TEMP_DIR}"

    case "${HELM_SECRETS_DRIVER:-sops}" in
    sops)
        ;;
    vault)
        if [ -f .dockerenv ]; then
            # If we run inside docker, we expect vault on this location
            export VAULT_ADDR=${VAULT_ADDR:-'http://vault:8200'}
        else
            export VAULT_ADDR=${VAULT_ADDR:-'http://127.0.0.1:8200'}
        fi

        vault login token=test

        _sed_i "s!put secret/!put secret/${SEED}/!g" "$(printf '%s/assets/values/vault/seed.sh' "${TEST_TEMP_DIR}")"

        _sed_i "s!vault secret/!vault secret/${SEED}/!g" "$(printf '%s/assets/values/vault/secrets.yaml' "${TEST_TEMP_DIR}")"
        _sed_i "s!vault secret/!vault secret/${SEED}/!g" "$(printf '%s/assets/values/vault/secrets.yaml' "${SPECIAL_CHAR_DIR}")"

        _sed_i "s!vault secret/!vault secret/${SEED}/!g" "$(printf '%s/assets/values/vault/some-secrets.yaml' "${TEST_TEMP_DIR}")"
        _sed_i "s!vault secret/!vault secret/${SEED}/!g" "$(printf '%s/assets/values/vault/some-secrets.yaml' "${SPECIAL_CHAR_DIR}")"

        sh "${TEST_TEMP_DIR}/assets/values/vault/seed.sh"
        ;;
    esac

    export _TEST_KEY="-----BEGIN PGP MESSAGE-----

wcFMAxYpv4YXKfBAARAAVzE7/FMD7+UWwMls23zKKLoTs+5w9GMvugn0wi5KOJ8P
PSrRY4r27VhwQH38gWDrzo3RCmO9414xZ0JW0HaN2Pgd3ml6mYCY/5RE7apgGZQI
3Im0fv8bhIwaP2UWPp74EXLzA3mh1dUtwxmuWOeoSq+Vm5NtbjkfUt/4MIcF5IAY
c+U4ZOdQlzgExwu+VtOpeBrkwfglh5fFuKqM8Fg1IICi/Pp6YAlpAdGqlt1zS4Pj
yjAS6eAvnpM0eA5hShuoO9JsAu4kVjaaBlipVpc1I2zdcT3H/1d7ASziwbKOm6jE
PJxzaMDxn0UfMjkhTaTZ8v27lz6W7qdlHdCWGGI348QkSoDotm7OzMC7ZLfps3+9
GrXo9Kwxkj6oy/thn92W2cRSeSD28g6kcUkHeG8L3mMv+gpTjIhM+Z8x3jJcVp2i
yoA2dO/kO2/HTcUfnEjppKigqUlRuKfDn8ercjYiq+foqtimH192iXXyRmltYlH0
GUSJ1FcNLAC9g0WLFPQnMFh5KxSweavpbdd6PILqEsyKvZpC5a+hzLKwGjWOveW1
K34QZf6Ay3CPCegAyGVjxmsg1vPKD+9WAZinveCl37l3cCQW1VZzbGkHgtLQ30Qr
DCRFZEstraLAQUf6VLAk9bPYX/fvkXmra970i/CfJjIg0SpOXbADBR4x+zRRZqrS
4AHkWTmhH/xXWyAgmh+sGs18OOFGfeC04AjhMmvg4uKzly6+4IDlNhPif2VpJYOi
EmU8gQoUsAHKYro0hPfzBZyJlL+TqCPgHeRPANVgm4Ww6RlVrNFpTy9H4m4s5y/h
EzAA
=jf7D
-----END PGP MESSAGE-----"
    export _TEST_global_secret=global_bar
    export _TEST_SERVICE_PORT=81
    export _TEST_SOME_SERVICE_PORT=83
}

teardown() {
    # https://stackoverflow.com/a/13864829/8087167
    if [ -n "${RELEASE+x}" ]; then
        helm del "${RELEASE}" >&2
    fi

    # https://github.com/bats-core/bats-core/issues/39#issuecomment-377015447
    if [[ "${#BATS_TEST_NAMES[@]}" -eq "$BATS_TEST_NUMBER" ]]; then
        HOME="${HELM_CACHE}" gpgconf --kill gpg-agent >&2
        temp_del "${HELM_CACHE}/.gnupg/"
    fi

    # https://github.com/bats-core/bats-file/pull/29
    chmod -R 777 "${TEST_TEMP_DIR}" >&2

    temp_del "${TEST_TEMP_DIR}"
    temp_del "${TEST_TEMP_HOME}"
}

create_chart() {
    {
        ln -sf "${HELM_CACHE}/chart/" "${1}"
    } >&2
}

helm_plugin_install() {
    {
        if _helm_cache plugin list | grep -q "${1}"; then
            return
        fi

        case "${1}" in
        kubeval)
            URL="https://github.com/instrumenta/helm-kubeval"
            ;;
        diff)
            URL="https://github.com/databus23/helm-diff"
            ;;
        git)
            URL="https://github.com/aslafy-z/helm-git"
            ;;
        secrets)
            URL="${GIT_ROOT}"
            ;;
        esac

        _helm_cache plugin install "${URL}" ${VERSION:+--version ${VERSION}}
    } >&2
}

on_windows() { true; }

case "$(uname -s)" in
Linux*) on_windows() { false; } ;;
Darwin*) on_windows() { false; }; ;;
esac

# MacOS syntax is different for in-place
# https://unix.stackexchange.com/a/92907/433641
case $(sed --help 2>&1) in
*BusyBox* | *GNU*) _sed_i() { sed -i "$@"; } ;;
*) _sed_i() { sed -i '' "$@"; } ;;
esac
