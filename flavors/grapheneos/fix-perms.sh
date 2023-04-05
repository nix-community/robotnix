#!@bash@/bin/bash

make_writeable() {
    for a in "$@"; do
        if [[ "$a" == ${OUT_DIR}*  ]] && [[ -e "$(realpath "$a")" ]]; then
            chmod u+w -R "$a"
        fi
    done
}

bash -c "exec -a cp $(dirname ''${BASH_SOURCE[0]})/.cp-wrapped $*" && make_writeable "$@"
