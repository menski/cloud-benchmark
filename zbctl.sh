# bash completion for zbctl                                -*- shell-script -*-

__zbctl_debug()
{
    if [[ -n ${BASH_COMP_DEBUG_FILE} ]]; then
        echo "$*" >> "${BASH_COMP_DEBUG_FILE}"
    fi
}

# Homebrew on Macs have version 1.3 of bash-completion which doesn't include
# _init_completion. This is a very minimal version of that function.
__zbctl_init_completion()
{
    COMPREPLY=()
    _get_comp_words_by_ref "$@" cur prev words cword
}

__zbctl_index_of_word()
{
    local w word=$1
    shift
    index=0
    for w in "$@"; do
        [[ $w = "$word" ]] && return
        index=$((index+1))
    done
    index=-1
}

__zbctl_contains_word()
{
    local w word=$1; shift
    for w in "$@"; do
        [[ $w = "$word" ]] && return
    done
    return 1
}

__zbctl_handle_reply()
{
    __zbctl_debug "${FUNCNAME[0]}"
    local comp
    case $cur in
        -*)
            if [[ $(type -t compopt) = "builtin" ]]; then
                compopt -o nospace
            fi
            local allflags
            if [ ${#must_have_one_flag[@]} -ne 0 ]; then
                allflags=("${must_have_one_flag[@]}")
            else
                allflags=("${flags[*]} ${two_word_flags[*]}")
            fi
            while IFS='' read -r comp; do
                COMPREPLY+=("$comp")
            done < <(compgen -W "${allflags[*]}" -- "$cur")
            if [[ $(type -t compopt) = "builtin" ]]; then
                [[ "${COMPREPLY[0]}" == *= ]] || compopt +o nospace
            fi

            # complete after --flag=abc
            if [[ $cur == *=* ]]; then
                if [[ $(type -t compopt) = "builtin" ]]; then
                    compopt +o nospace
                fi

                local index flag
                flag="${cur%=*}"
                __zbctl_index_of_word "${flag}" "${flags_with_completion[@]}"
                COMPREPLY=()
                if [[ ${index} -ge 0 ]]; then
                    PREFIX=""
                    cur="${cur#*=}"
                    ${flags_completion[${index}]}
                    if [ -n "${ZSH_VERSION}" ]; then
                        # zsh completion needs --flag= prefix
                        eval "COMPREPLY=( \"\${COMPREPLY[@]/#/${flag}=}\" )"
                    fi
                fi
            fi
            return 0;
            ;;
    esac

    # check if we are handling a flag with special work handling
    local index
    __zbctl_index_of_word "${prev}" "${flags_with_completion[@]}"
    if [[ ${index} -ge 0 ]]; then
        ${flags_completion[${index}]}
        return
    fi

    # we are parsing a flag and don't have a special handler, no completion
    if [[ ${cur} != "${words[cword]}" ]]; then
        return
    fi

    local completions
    completions=("${commands[@]}")
    if [[ ${#must_have_one_noun[@]} -ne 0 ]]; then
        completions=("${must_have_one_noun[@]}")
    fi
    if [[ ${#must_have_one_flag[@]} -ne 0 ]]; then
        completions+=("${must_have_one_flag[@]}")
    fi
    while IFS='' read -r comp; do
        COMPREPLY+=("$comp")
    done < <(compgen -W "${completions[*]}" -- "$cur")

    if [[ ${#COMPREPLY[@]} -eq 0 && ${#noun_aliases[@]} -gt 0 && ${#must_have_one_noun[@]} -ne 0 ]]; then
        while IFS='' read -r comp; do
            COMPREPLY+=("$comp")
        done < <(compgen -W "${noun_aliases[*]}" -- "$cur")
    fi

    if [[ ${#COMPREPLY[@]} -eq 0 ]]; then
		if declare -F __zbctl_custom_func >/dev/null; then
			# try command name qualified custom func
			__zbctl_custom_func
		else
			# otherwise fall back to unqualified for compatibility
			declare -F __custom_func >/dev/null && __custom_func
		fi
    fi

    # available in bash-completion >= 2, not always present on macOS
    if declare -F __ltrim_colon_completions >/dev/null; then
        __ltrim_colon_completions "$cur"
    fi

    # If there is only 1 completion and it is a flag with an = it will be completed
    # but we don't want a space after the =
    if [[ "${#COMPREPLY[@]}" -eq "1" ]] && [[ $(type -t compopt) = "builtin" ]] && [[ "${COMPREPLY[0]}" == --*= ]]; then
       compopt -o nospace
    fi
}

# The arguments should be in the form "ext1|ext2|extn"
__zbctl_handle_filename_extension_flag()
{
    local ext="$1"
    _filedir "@(${ext})"
}

__zbctl_handle_subdirs_in_dir_flag()
{
    local dir="$1"
    pushd "${dir}" >/dev/null 2>&1 && _filedir -d && popd >/dev/null 2>&1 || return
}

__zbctl_handle_flag()
{
    __zbctl_debug "${FUNCNAME[0]}: c is $c words[c] is ${words[c]}"

    # if a command required a flag, and we found it, unset must_have_one_flag()
    local flagname=${words[c]}
    local flagvalue
    # if the word contained an =
    if [[ ${words[c]} == *"="* ]]; then
        flagvalue=${flagname#*=} # take in as flagvalue after the =
        flagname=${flagname%=*} # strip everything after the =
        flagname="${flagname}=" # but put the = back
    fi
    __zbctl_debug "${FUNCNAME[0]}: looking for ${flagname}"
    if __zbctl_contains_word "${flagname}" "${must_have_one_flag[@]}"; then
        must_have_one_flag=()
    fi

    # if you set a flag which only applies to this command, don't show subcommands
    if __zbctl_contains_word "${flagname}" "${local_nonpersistent_flags[@]}"; then
      commands=()
    fi

    # keep flag value with flagname as flaghash
    # flaghash variable is an associative array which is only supported in bash > 3.
    if [[ -z "${BASH_VERSION}" || "${BASH_VERSINFO[0]}" -gt 3 ]]; then
        if [ -n "${flagvalue}" ] ; then
            flaghash[${flagname}]=${flagvalue}
        elif [ -n "${words[ $((c+1)) ]}" ] ; then
            flaghash[${flagname}]=${words[ $((c+1)) ]}
        else
            flaghash[${flagname}]="true" # pad "true" for bool flag
        fi
    fi

    # skip the argument to a two word flag
    if [[ ${words[c]} != *"="* ]] && __zbctl_contains_word "${words[c]}" "${two_word_flags[@]}"; then
			  __zbctl_debug "${FUNCNAME[0]}: found a flag ${words[c]}, skip the next argument"
        c=$((c+1))
        # if we are looking for a flags value, don't show commands
        if [[ $c -eq $cword ]]; then
            commands=()
        fi
    fi

    c=$((c+1))

}

__zbctl_handle_noun()
{
    __zbctl_debug "${FUNCNAME[0]}: c is $c words[c] is ${words[c]}"

    if __zbctl_contains_word "${words[c]}" "${must_have_one_noun[@]}"; then
        must_have_one_noun=()
    elif __zbctl_contains_word "${words[c]}" "${noun_aliases[@]}"; then
        must_have_one_noun=()
    fi

    nouns+=("${words[c]}")
    c=$((c+1))
}

__zbctl_handle_command()
{
    __zbctl_debug "${FUNCNAME[0]}: c is $c words[c] is ${words[c]}"

    local next_command
    if [[ -n ${last_command} ]]; then
        next_command="_${last_command}_${words[c]//:/__}"
    else
        if [[ $c -eq 0 ]]; then
            next_command="_zbctl_root_command"
        else
            next_command="_${words[c]//:/__}"
        fi
    fi
    c=$((c+1))
    __zbctl_debug "${FUNCNAME[0]}: looking for ${next_command}"
    declare -F "$next_command" >/dev/null && $next_command
}

__zbctl_handle_word()
{
    if [[ $c -ge $cword ]]; then
        __zbctl_handle_reply
        return
    fi
    __zbctl_debug "${FUNCNAME[0]}: c is $c words[c] is ${words[c]}"
    if [[ "${words[c]}" == -* ]]; then
        __zbctl_handle_flag
    elif __zbctl_contains_word "${words[c]}" "${commands[@]}"; then
        __zbctl_handle_command
    elif [[ $c -eq 0 ]]; then
        __zbctl_handle_command
    elif __zbctl_contains_word "${words[c]}" "${command_aliases[@]}"; then
        # aliashash variable is an associative array which is only supported in bash > 3.
        if [[ -z "${BASH_VERSION}" || "${BASH_VERSINFO[0]}" -gt 3 ]]; then
            words[c]=${aliashash[${words[c]}]}
            __zbctl_handle_command
        else
            __zbctl_handle_noun
        fi
    else
        __zbctl_handle_noun
    fi
    __zbctl_handle_word
}

_zbctl_activate_jobs()
{
    last_command="zbctl_activate_jobs"

    command_aliases=()

    commands=()

    flags=()
    two_word_flags=()
    local_nonpersistent_flags=()
    flags_with_completion=()
    flags_completion=()

    flags+=("--maxJobsToActivate=")
    two_word_flags+=("--maxJobsToActivate")
    local_nonpersistent_flags+=("--maxJobsToActivate=")
    flags+=("--requestTimeout=")
    two_word_flags+=("--requestTimeout")
    local_nonpersistent_flags+=("--requestTimeout=")
    flags+=("--timeout=")
    two_word_flags+=("--timeout")
    local_nonpersistent_flags+=("--timeout=")
    flags+=("--variables=")
    two_word_flags+=("--variables")
    local_nonpersistent_flags+=("--variables=")
    flags+=("--worker=")
    two_word_flags+=("--worker")
    local_nonpersistent_flags+=("--worker=")
    flags+=("--address=")
    two_word_flags+=("--address")
    flags+=("--audience=")
    two_word_flags+=("--audience")
    flags+=("--authzUrl=")
    two_word_flags+=("--authzUrl")
    flags+=("--certPath=")
    two_word_flags+=("--certPath")
    flags+=("--clientCache=")
    two_word_flags+=("--clientCache")
    flags+=("--clientId=")
    two_word_flags+=("--clientId")
    flags+=("--clientSecret=")
    two_word_flags+=("--clientSecret")
    flags+=("--insecure")

    must_have_one_flag=()
    must_have_one_noun=()
    noun_aliases=()
}

_zbctl_activate()
{
    last_command="zbctl_activate"

    command_aliases=()

    commands=()
    commands+=("jobs")

    flags=()
    two_word_flags=()
    local_nonpersistent_flags=()
    flags_with_completion=()
    flags_completion=()

    flags+=("--address=")
    two_word_flags+=("--address")
    flags+=("--audience=")
    two_word_flags+=("--audience")
    flags+=("--authzUrl=")
    two_word_flags+=("--authzUrl")
    flags+=("--certPath=")
    two_word_flags+=("--certPath")
    flags+=("--clientCache=")
    two_word_flags+=("--clientCache")
    flags+=("--clientId=")
    two_word_flags+=("--clientId")
    flags+=("--clientSecret=")
    two_word_flags+=("--clientSecret")
    flags+=("--insecure")

    must_have_one_flag=()
    must_have_one_noun=()
    noun_aliases=()
}

_zbctl_cancel_instance()
{
    last_command="zbctl_cancel_instance"

    command_aliases=()

    commands=()

    flags=()
    two_word_flags=()
    local_nonpersistent_flags=()
    flags_with_completion=()
    flags_completion=()

    flags+=("--address=")
    two_word_flags+=("--address")
    flags+=("--audience=")
    two_word_flags+=("--audience")
    flags+=("--authzUrl=")
    two_word_flags+=("--authzUrl")
    flags+=("--certPath=")
    two_word_flags+=("--certPath")
    flags+=("--clientCache=")
    two_word_flags+=("--clientCache")
    flags+=("--clientId=")
    two_word_flags+=("--clientId")
    flags+=("--clientSecret=")
    two_word_flags+=("--clientSecret")
    flags+=("--insecure")

    must_have_one_flag=()
    must_have_one_noun=()
    noun_aliases=()
}

_zbctl_cancel()
{
    last_command="zbctl_cancel"

    command_aliases=()

    commands=()
    commands+=("instance")

    flags=()
    two_word_flags=()
    local_nonpersistent_flags=()
    flags_with_completion=()
    flags_completion=()

    flags+=("--address=")
    two_word_flags+=("--address")
    flags+=("--audience=")
    two_word_flags+=("--audience")
    flags+=("--authzUrl=")
    two_word_flags+=("--authzUrl")
    flags+=("--certPath=")
    two_word_flags+=("--certPath")
    flags+=("--clientCache=")
    two_word_flags+=("--clientCache")
    flags+=("--clientId=")
    two_word_flags+=("--clientId")
    flags+=("--clientSecret=")
    two_word_flags+=("--clientSecret")
    flags+=("--insecure")

    must_have_one_flag=()
    must_have_one_noun=()
    noun_aliases=()
}

_zbctl_complete_job()
{
    last_command="zbctl_complete_job"

    command_aliases=()

    commands=()

    flags=()
    two_word_flags=()
    local_nonpersistent_flags=()
    flags_with_completion=()
    flags_completion=()

    flags+=("--variables=")
    two_word_flags+=("--variables")
    local_nonpersistent_flags+=("--variables=")
    flags+=("--address=")
    two_word_flags+=("--address")
    flags+=("--audience=")
    two_word_flags+=("--audience")
    flags+=("--authzUrl=")
    two_word_flags+=("--authzUrl")
    flags+=("--certPath=")
    two_word_flags+=("--certPath")
    flags+=("--clientCache=")
    two_word_flags+=("--clientCache")
    flags+=("--clientId=")
    two_word_flags+=("--clientId")
    flags+=("--clientSecret=")
    two_word_flags+=("--clientSecret")
    flags+=("--insecure")

    must_have_one_flag=()
    must_have_one_noun=()
    noun_aliases=()
}

_zbctl_complete()
{
    last_command="zbctl_complete"

    command_aliases=()

    commands=()
    commands+=("job")

    flags=()
    two_word_flags=()
    local_nonpersistent_flags=()
    flags_with_completion=()
    flags_completion=()

    flags+=("--address=")
    two_word_flags+=("--address")
    flags+=("--audience=")
    two_word_flags+=("--audience")
    flags+=("--authzUrl=")
    two_word_flags+=("--authzUrl")
    flags+=("--certPath=")
    two_word_flags+=("--certPath")
    flags+=("--clientCache=")
    two_word_flags+=("--clientCache")
    flags+=("--clientId=")
    two_word_flags+=("--clientId")
    flags+=("--clientSecret=")
    two_word_flags+=("--clientSecret")
    flags+=("--insecure")

    must_have_one_flag=()
    must_have_one_noun=()
    noun_aliases=()
}

_zbctl_create_instance()
{
    last_command="zbctl_create_instance"

    command_aliases=()

    commands=()

    flags=()
    two_word_flags=()
    local_nonpersistent_flags=()
    flags_with_completion=()
    flags_completion=()

    flags+=("--variables=")
    two_word_flags+=("--variables")
    local_nonpersistent_flags+=("--variables=")
    flags+=("--version=")
    two_word_flags+=("--version")
    local_nonpersistent_flags+=("--version=")
    flags+=("--withResult")
    local_nonpersistent_flags+=("--withResult")
    flags+=("--address=")
    two_word_flags+=("--address")
    flags+=("--audience=")
    two_word_flags+=("--audience")
    flags+=("--authzUrl=")
    two_word_flags+=("--authzUrl")
    flags+=("--certPath=")
    two_word_flags+=("--certPath")
    flags+=("--clientCache=")
    two_word_flags+=("--clientCache")
    flags+=("--clientId=")
    two_word_flags+=("--clientId")
    flags+=("--clientSecret=")
    two_word_flags+=("--clientSecret")
    flags+=("--insecure")

    must_have_one_flag=()
    must_have_one_noun=()
    noun_aliases=()
}

_zbctl_create_worker()
{
    last_command="zbctl_create_worker"

    command_aliases=()

    commands=()

    flags=()
    two_word_flags=()
    local_nonpersistent_flags=()
    flags_with_completion=()
    flags_completion=()

    flags+=("--concurrency=")
    two_word_flags+=("--concurrency")
    local_nonpersistent_flags+=("--concurrency=")
    flags+=("--handler=")
    two_word_flags+=("--handler")
    local_nonpersistent_flags+=("--handler=")
    flags+=("--maxJobsActive=")
    two_word_flags+=("--maxJobsActive")
    local_nonpersistent_flags+=("--maxJobsActive=")
    flags+=("--name=")
    two_word_flags+=("--name")
    local_nonpersistent_flags+=("--name=")
    flags+=("--pollInterval=")
    two_word_flags+=("--pollInterval")
    local_nonpersistent_flags+=("--pollInterval=")
    flags+=("--pollThreshold=")
    two_word_flags+=("--pollThreshold")
    local_nonpersistent_flags+=("--pollThreshold=")
    flags+=("--requestTimeout=")
    two_word_flags+=("--requestTimeout")
    local_nonpersistent_flags+=("--requestTimeout=")
    flags+=("--timeout=")
    two_word_flags+=("--timeout")
    local_nonpersistent_flags+=("--timeout=")
    flags+=("--address=")
    two_word_flags+=("--address")
    flags+=("--audience=")
    two_word_flags+=("--audience")
    flags+=("--authzUrl=")
    two_word_flags+=("--authzUrl")
    flags+=("--certPath=")
    two_word_flags+=("--certPath")
    flags+=("--clientCache=")
    two_word_flags+=("--clientCache")
    flags+=("--clientId=")
    two_word_flags+=("--clientId")
    flags+=("--clientSecret=")
    two_word_flags+=("--clientSecret")
    flags+=("--insecure")

    must_have_one_flag=()
    must_have_one_flag+=("--handler=")
    must_have_one_noun=()
    noun_aliases=()
}

_zbctl_create()
{
    last_command="zbctl_create"

    command_aliases=()

    commands=()
    commands+=("instance")
    commands+=("worker")

    flags=()
    two_word_flags=()
    local_nonpersistent_flags=()
    flags_with_completion=()
    flags_completion=()

    flags+=("--address=")
    two_word_flags+=("--address")
    flags+=("--audience=")
    two_word_flags+=("--audience")
    flags+=("--authzUrl=")
    two_word_flags+=("--authzUrl")
    flags+=("--certPath=")
    two_word_flags+=("--certPath")
    flags+=("--clientCache=")
    two_word_flags+=("--clientCache")
    flags+=("--clientId=")
    two_word_flags+=("--clientId")
    flags+=("--clientSecret=")
    two_word_flags+=("--clientSecret")
    flags+=("--insecure")

    must_have_one_flag=()
    must_have_one_noun=()
    noun_aliases=()
}

_zbctl_deploy()
{
    last_command="zbctl_deploy"

    command_aliases=()

    commands=()

    flags=()
    two_word_flags=()
    local_nonpersistent_flags=()
    flags_with_completion=()
    flags_completion=()

    flags+=("--address=")
    two_word_flags+=("--address")
    flags+=("--audience=")
    two_word_flags+=("--audience")
    flags+=("--authzUrl=")
    two_word_flags+=("--authzUrl")
    flags+=("--certPath=")
    two_word_flags+=("--certPath")
    flags+=("--clientCache=")
    two_word_flags+=("--clientCache")
    flags+=("--clientId=")
    two_word_flags+=("--clientId")
    flags+=("--clientSecret=")
    two_word_flags+=("--clientSecret")
    flags+=("--insecure")

    must_have_one_flag=()
    must_have_one_noun=()
    noun_aliases=()
}

_zbctl_fail_job()
{
    last_command="zbctl_fail_job"

    command_aliases=()

    commands=()

    flags=()
    two_word_flags=()
    local_nonpersistent_flags=()
    flags_with_completion=()
    flags_completion=()

    flags+=("--errorMessage=")
    two_word_flags+=("--errorMessage")
    local_nonpersistent_flags+=("--errorMessage=")
    flags+=("--retries=")
    two_word_flags+=("--retries")
    local_nonpersistent_flags+=("--retries=")
    flags+=("--address=")
    two_word_flags+=("--address")
    flags+=("--audience=")
    two_word_flags+=("--audience")
    flags+=("--authzUrl=")
    two_word_flags+=("--authzUrl")
    flags+=("--certPath=")
    two_word_flags+=("--certPath")
    flags+=("--clientCache=")
    two_word_flags+=("--clientCache")
    flags+=("--clientId=")
    two_word_flags+=("--clientId")
    flags+=("--clientSecret=")
    two_word_flags+=("--clientSecret")
    flags+=("--insecure")

    must_have_one_flag=()
    must_have_one_flag+=("--retries=")
    must_have_one_noun=()
    noun_aliases=()
}

_zbctl_fail()
{
    last_command="zbctl_fail"

    command_aliases=()

    commands=()
    commands+=("job")

    flags=()
    two_word_flags=()
    local_nonpersistent_flags=()
    flags_with_completion=()
    flags_completion=()

    flags+=("--address=")
    two_word_flags+=("--address")
    flags+=("--audience=")
    two_word_flags+=("--audience")
    flags+=("--authzUrl=")
    two_word_flags+=("--authzUrl")
    flags+=("--certPath=")
    two_word_flags+=("--certPath")
    flags+=("--clientCache=")
    two_word_flags+=("--clientCache")
    flags+=("--clientId=")
    two_word_flags+=("--clientId")
    flags+=("--clientSecret=")
    two_word_flags+=("--clientSecret")
    flags+=("--insecure")

    must_have_one_flag=()
    must_have_one_noun=()
    noun_aliases=()
}

_zbctl_generate_completion()
{
    last_command="zbctl_generate_completion"

    command_aliases=()

    commands=()

    flags=()
    two_word_flags=()
    local_nonpersistent_flags=()
    flags_with_completion=()
    flags_completion=()

    flags+=("--help")
    flags+=("-h")
    local_nonpersistent_flags+=("--help")
    flags+=("--shell=")
    two_word_flags+=("--shell")
    local_nonpersistent_flags+=("--shell=")
    flags+=("--address=")
    two_word_flags+=("--address")
    flags+=("--audience=")
    two_word_flags+=("--audience")
    flags+=("--authzUrl=")
    two_word_flags+=("--authzUrl")
    flags+=("--certPath=")
    two_word_flags+=("--certPath")
    flags+=("--clientCache=")
    two_word_flags+=("--clientCache")
    flags+=("--clientId=")
    two_word_flags+=("--clientId")
    flags+=("--clientSecret=")
    two_word_flags+=("--clientSecret")
    flags+=("--insecure")

    must_have_one_flag=()
    must_have_one_noun=()
    noun_aliases=()
}

_zbctl_generate()
{
    last_command="zbctl_generate"

    command_aliases=()

    commands=()
    commands+=("completion")

    flags=()
    two_word_flags=()
    local_nonpersistent_flags=()
    flags_with_completion=()
    flags_completion=()

    flags+=("--address=")
    two_word_flags+=("--address")
    flags+=("--audience=")
    two_word_flags+=("--audience")
    flags+=("--authzUrl=")
    two_word_flags+=("--authzUrl")
    flags+=("--certPath=")
    two_word_flags+=("--certPath")
    flags+=("--clientCache=")
    two_word_flags+=("--clientCache")
    flags+=("--clientId=")
    two_word_flags+=("--clientId")
    flags+=("--clientSecret=")
    two_word_flags+=("--clientSecret")
    flags+=("--insecure")

    must_have_one_flag=()
    must_have_one_noun=()
    noun_aliases=()
}

_zbctl_publish_message()
{
    last_command="zbctl_publish_message"

    command_aliases=()

    commands=()

    flags=()
    two_word_flags=()
    local_nonpersistent_flags=()
    flags_with_completion=()
    flags_completion=()

    flags+=("--correlationKey=")
    two_word_flags+=("--correlationKey")
    local_nonpersistent_flags+=("--correlationKey=")
    flags+=("--messageId=")
    two_word_flags+=("--messageId")
    local_nonpersistent_flags+=("--messageId=")
    flags+=("--ttl=")
    two_word_flags+=("--ttl")
    local_nonpersistent_flags+=("--ttl=")
    flags+=("--variables=")
    two_word_flags+=("--variables")
    local_nonpersistent_flags+=("--variables=")
    flags+=("--address=")
    two_word_flags+=("--address")
    flags+=("--audience=")
    two_word_flags+=("--audience")
    flags+=("--authzUrl=")
    two_word_flags+=("--authzUrl")
    flags+=("--certPath=")
    two_word_flags+=("--certPath")
    flags+=("--clientCache=")
    two_word_flags+=("--clientCache")
    flags+=("--clientId=")
    two_word_flags+=("--clientId")
    flags+=("--clientSecret=")
    two_word_flags+=("--clientSecret")
    flags+=("--insecure")

    must_have_one_flag=()
    must_have_one_flag+=("--correlationKey=")
    must_have_one_noun=()
    noun_aliases=()
}

_zbctl_publish()
{
    last_command="zbctl_publish"

    command_aliases=()

    commands=()
    commands+=("message")

    flags=()
    two_word_flags=()
    local_nonpersistent_flags=()
    flags_with_completion=()
    flags_completion=()

    flags+=("--address=")
    two_word_flags+=("--address")
    flags+=("--audience=")
    two_word_flags+=("--audience")
    flags+=("--authzUrl=")
    two_word_flags+=("--authzUrl")
    flags+=("--certPath=")
    two_word_flags+=("--certPath")
    flags+=("--clientCache=")
    two_word_flags+=("--clientCache")
    flags+=("--clientId=")
    two_word_flags+=("--clientId")
    flags+=("--clientSecret=")
    two_word_flags+=("--clientSecret")
    flags+=("--insecure")

    must_have_one_flag=()
    must_have_one_noun=()
    noun_aliases=()
}

_zbctl_resolve_incident()
{
    last_command="zbctl_resolve_incident"

    command_aliases=()

    commands=()

    flags=()
    two_word_flags=()
    local_nonpersistent_flags=()
    flags_with_completion=()
    flags_completion=()

    flags+=("--address=")
    two_word_flags+=("--address")
    flags+=("--audience=")
    two_word_flags+=("--audience")
    flags+=("--authzUrl=")
    two_word_flags+=("--authzUrl")
    flags+=("--certPath=")
    two_word_flags+=("--certPath")
    flags+=("--clientCache=")
    two_word_flags+=("--clientCache")
    flags+=("--clientId=")
    two_word_flags+=("--clientId")
    flags+=("--clientSecret=")
    two_word_flags+=("--clientSecret")
    flags+=("--insecure")

    must_have_one_flag=()
    must_have_one_noun=()
    noun_aliases=()
}

_zbctl_resolve()
{
    last_command="zbctl_resolve"

    command_aliases=()

    commands=()
    commands+=("incident")

    flags=()
    two_word_flags=()
    local_nonpersistent_flags=()
    flags_with_completion=()
    flags_completion=()

    flags+=("--address=")
    two_word_flags+=("--address")
    flags+=("--audience=")
    two_word_flags+=("--audience")
    flags+=("--authzUrl=")
    two_word_flags+=("--authzUrl")
    flags+=("--certPath=")
    two_word_flags+=("--certPath")
    flags+=("--clientCache=")
    two_word_flags+=("--clientCache")
    flags+=("--clientId=")
    two_word_flags+=("--clientId")
    flags+=("--clientSecret=")
    two_word_flags+=("--clientSecret")
    flags+=("--insecure")

    must_have_one_flag=()
    must_have_one_noun=()
    noun_aliases=()
}

_zbctl_set_variables()
{
    last_command="zbctl_set_variables"

    command_aliases=()

    commands=()

    flags=()
    two_word_flags=()
    local_nonpersistent_flags=()
    flags_with_completion=()
    flags_completion=()

    flags+=("--local")
    local_nonpersistent_flags+=("--local")
    flags+=("--variables=")
    two_word_flags+=("--variables")
    local_nonpersistent_flags+=("--variables=")
    flags+=("--address=")
    two_word_flags+=("--address")
    flags+=("--audience=")
    two_word_flags+=("--audience")
    flags+=("--authzUrl=")
    two_word_flags+=("--authzUrl")
    flags+=("--certPath=")
    two_word_flags+=("--certPath")
    flags+=("--clientCache=")
    two_word_flags+=("--clientCache")
    flags+=("--clientId=")
    two_word_flags+=("--clientId")
    flags+=("--clientSecret=")
    two_word_flags+=("--clientSecret")
    flags+=("--insecure")

    must_have_one_flag=()
    must_have_one_flag+=("--variables=")
    must_have_one_noun=()
    noun_aliases=()
}

_zbctl_set()
{
    last_command="zbctl_set"

    command_aliases=()

    commands=()
    commands+=("variables")

    flags=()
    two_word_flags=()
    local_nonpersistent_flags=()
    flags_with_completion=()
    flags_completion=()

    flags+=("--address=")
    two_word_flags+=("--address")
    flags+=("--audience=")
    two_word_flags+=("--audience")
    flags+=("--authzUrl=")
    two_word_flags+=("--authzUrl")
    flags+=("--certPath=")
    two_word_flags+=("--certPath")
    flags+=("--clientCache=")
    two_word_flags+=("--clientCache")
    flags+=("--clientId=")
    two_word_flags+=("--clientId")
    flags+=("--clientSecret=")
    two_word_flags+=("--clientSecret")
    flags+=("--insecure")

    must_have_one_flag=()
    must_have_one_noun=()
    noun_aliases=()
}

_zbctl_status()
{
    last_command="zbctl_status"

    command_aliases=()

    commands=()

    flags=()
    two_word_flags=()
    local_nonpersistent_flags=()
    flags_with_completion=()
    flags_completion=()

    flags+=("--address=")
    two_word_flags+=("--address")
    flags+=("--audience=")
    two_word_flags+=("--audience")
    flags+=("--authzUrl=")
    two_word_flags+=("--authzUrl")
    flags+=("--certPath=")
    two_word_flags+=("--certPath")
    flags+=("--clientCache=")
    two_word_flags+=("--clientCache")
    flags+=("--clientId=")
    two_word_flags+=("--clientId")
    flags+=("--clientSecret=")
    two_word_flags+=("--clientSecret")
    flags+=("--insecure")

    must_have_one_flag=()
    must_have_one_noun=()
    noun_aliases=()
}

_zbctl_throwError_job()
{
    last_command="zbctl_throwError_job"

    command_aliases=()

    commands=()

    flags=()
    two_word_flags=()
    local_nonpersistent_flags=()
    flags_with_completion=()
    flags_completion=()

    flags+=("--errorCode=")
    two_word_flags+=("--errorCode")
    local_nonpersistent_flags+=("--errorCode=")
    flags+=("--errorMessage=")
    two_word_flags+=("--errorMessage")
    local_nonpersistent_flags+=("--errorMessage=")
    flags+=("--address=")
    two_word_flags+=("--address")
    flags+=("--audience=")
    two_word_flags+=("--audience")
    flags+=("--authzUrl=")
    two_word_flags+=("--authzUrl")
    flags+=("--certPath=")
    two_word_flags+=("--certPath")
    flags+=("--clientCache=")
    two_word_flags+=("--clientCache")
    flags+=("--clientId=")
    two_word_flags+=("--clientId")
    flags+=("--clientSecret=")
    two_word_flags+=("--clientSecret")
    flags+=("--insecure")

    must_have_one_flag=()
    must_have_one_flag+=("--errorCode=")
    must_have_one_noun=()
    noun_aliases=()
}

_zbctl_throwError()
{
    last_command="zbctl_throwError"

    command_aliases=()

    commands=()
    commands+=("job")

    flags=()
    two_word_flags=()
    local_nonpersistent_flags=()
    flags_with_completion=()
    flags_completion=()

    flags+=("--address=")
    two_word_flags+=("--address")
    flags+=("--audience=")
    two_word_flags+=("--audience")
    flags+=("--authzUrl=")
    two_word_flags+=("--authzUrl")
    flags+=("--certPath=")
    two_word_flags+=("--certPath")
    flags+=("--clientCache=")
    two_word_flags+=("--clientCache")
    flags+=("--clientId=")
    two_word_flags+=("--clientId")
    flags+=("--clientSecret=")
    two_word_flags+=("--clientSecret")
    flags+=("--insecure")

    must_have_one_flag=()
    must_have_one_noun=()
    noun_aliases=()
}

_zbctl_update_retries()
{
    last_command="zbctl_update_retries"

    command_aliases=()

    commands=()

    flags=()
    two_word_flags=()
    local_nonpersistent_flags=()
    flags_with_completion=()
    flags_completion=()

    flags+=("--retries=")
    two_word_flags+=("--retries")
    local_nonpersistent_flags+=("--retries=")
    flags+=("--address=")
    two_word_flags+=("--address")
    flags+=("--audience=")
    two_word_flags+=("--audience")
    flags+=("--authzUrl=")
    two_word_flags+=("--authzUrl")
    flags+=("--certPath=")
    two_word_flags+=("--certPath")
    flags+=("--clientCache=")
    two_word_flags+=("--clientCache")
    flags+=("--clientId=")
    two_word_flags+=("--clientId")
    flags+=("--clientSecret=")
    two_word_flags+=("--clientSecret")
    flags+=("--insecure")

    must_have_one_flag=()
    must_have_one_flag+=("--retries=")
    must_have_one_noun=()
    noun_aliases=()
}

_zbctl_update()
{
    last_command="zbctl_update"

    command_aliases=()

    commands=()
    commands+=("retries")

    flags=()
    two_word_flags=()
    local_nonpersistent_flags=()
    flags_with_completion=()
    flags_completion=()

    flags+=("--address=")
    two_word_flags+=("--address")
    flags+=("--audience=")
    two_word_flags+=("--audience")
    flags+=("--authzUrl=")
    two_word_flags+=("--authzUrl")
    flags+=("--certPath=")
    two_word_flags+=("--certPath")
    flags+=("--clientCache=")
    two_word_flags+=("--clientCache")
    flags+=("--clientId=")
    two_word_flags+=("--clientId")
    flags+=("--clientSecret=")
    two_word_flags+=("--clientSecret")
    flags+=("--insecure")

    must_have_one_flag=()
    must_have_one_noun=()
    noun_aliases=()
}

_zbctl_version()
{
    last_command="zbctl_version"

    command_aliases=()

    commands=()

    flags=()
    two_word_flags=()
    local_nonpersistent_flags=()
    flags_with_completion=()
    flags_completion=()

    flags+=("--address=")
    two_word_flags+=("--address")
    flags+=("--audience=")
    two_word_flags+=("--audience")
    flags+=("--authzUrl=")
    two_word_flags+=("--authzUrl")
    flags+=("--certPath=")
    two_word_flags+=("--certPath")
    flags+=("--clientCache=")
    two_word_flags+=("--clientCache")
    flags+=("--clientId=")
    two_word_flags+=("--clientId")
    flags+=("--clientSecret=")
    two_word_flags+=("--clientSecret")
    flags+=("--insecure")

    must_have_one_flag=()
    must_have_one_noun=()
    noun_aliases=()
}

_zbctl_root_command()
{
    last_command="zbctl"

    command_aliases=()

    commands=()
    commands+=("activate")
    commands+=("cancel")
    commands+=("complete")
    commands+=("create")
    commands+=("deploy")
    commands+=("fail")
    commands+=("generate")
    commands+=("publish")
    commands+=("resolve")
    commands+=("set")
    commands+=("status")
    commands+=("throwError")
    commands+=("update")
    commands+=("version")

    flags=()
    two_word_flags=()
    local_nonpersistent_flags=()
    flags_with_completion=()
    flags_completion=()

    flags+=("--address=")
    two_word_flags+=("--address")
    flags+=("--audience=")
    two_word_flags+=("--audience")
    flags+=("--authzUrl=")
    two_word_flags+=("--authzUrl")
    flags+=("--certPath=")
    two_word_flags+=("--certPath")
    flags+=("--clientCache=")
    two_word_flags+=("--clientCache")
    flags+=("--clientId=")
    two_word_flags+=("--clientId")
    flags+=("--clientSecret=")
    two_word_flags+=("--clientSecret")
    flags+=("--insecure")

    must_have_one_flag=()
    must_have_one_noun=()
    noun_aliases=()
}

__start_zbctl()
{
    local cur prev words cword
    declare -A flaghash 2>/dev/null || :
    declare -A aliashash 2>/dev/null || :
    if declare -F _init_completion >/dev/null 2>&1; then
        _init_completion -s || return
    else
        __zbctl_init_completion -n "=" || return
    fi

    local c=0
    local flags=()
    local two_word_flags=()
    local local_nonpersistent_flags=()
    local flags_with_completion=()
    local flags_completion=()
    local commands=("zbctl")
    local must_have_one_flag=()
    local must_have_one_noun=()
    local last_command
    local nouns=()

    __zbctl_handle_word
}

if [[ $(type -t compopt) = "builtin" ]]; then
    complete -o default -F __start_zbctl zbctl
else
    complete -o default -o nospace -F __start_zbctl zbctl
fi

# ex: ts=4 sw=4 et filetype=sh
