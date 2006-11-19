THIS=${0##*/}

# Portable which(1).
pathfind () {
    ifs_save="$IFS"
    IFS=:
    for _p in $PATH; do
        if [ -x "$_p/$*" ] && [ -f "$_p/$*" ]; then
            IFS="$OLDIFS"
            return 0
        fi
    done
    IFS="$ifs_save"
    return 1
}

if pathfind iconv; then
    alias _to_utf8='iconv -t utf-8'
    alias _from_utf8='iconv -t utf-8'
else
    alias _to_utf8='cat'
    alias _from_utf8='cat'
fi

safein () {
    _to_utf8 "${1:--}" # safe-guarded against an "" argument
}

safeout () {
    if [ -z "$1" ]; then
	_from_utf8
	return
    fi

    if [ -z "$2" ]; then
	src=${TMPDIR-/tmp}/${THIS}.$$
	dest="$1"
	trap "status=$?; rm -rf $src; exit $status" INT QUIT TERM EXIT
	_from_utf8 >$src
    else
	src="$1"
	dest="$2"
    fi

    is_target_exists=
    if [ -f "$dest" ]; then
	is_target_exists=1
	mv -f "$dest" "$dest~"
    fi

    mv -f "$src" "$dest"

    printf "Created '$dest'" >&2
    [ -z "$is_target_exists" ] || {
	printf " (previous file has been backed up as '$dest~')" >&2
    }
    echo >&2 .
}

for p in pandoc $REQUIRED; do
    pathfind $p || {
        echo >&2 "You need '$p' to use this program!"
        exit 1
    }
done
