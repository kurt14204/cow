#!/bin/bash

cd "$( dirname "${BASH_SOURCE[0]}" )/.."

if ! go build; then
    echo "build failed"
    exit 1
fi

PROXY_ADDR=127.0.0.1:7788

if [[ -z "$TRAVIS" ]]; then
    ./cow -rc ~/.cow/debugrc -listen=$PROXY_ADDR &
else
    # on travis
    ./cow -rc ./script/debugrc -listen=$PROXY_ADDR &
fi
cow_pid=$!
sleep 0.5

test_get() {
    local url
    url=$1
    target=$2
    noproxy=$3
    code=$4

    if [[ -z $code ]]; then
        code="200"
    fi

    # get 5 times
    for i in {1..2}; do
        # -s silent to disable progress meter, but enable --show-error 
        # -i to include http header
        # -L to follow redirect so we should always get HTTP 200
        if [[ -n $noproxy ]]; then
            cont=`curl -s --show-error -i -L $url 2>&1`
        else
            cont=`curl -s --show-error -i -L -x $PROXY_ADDR $url 2>&1`
        fi
        ok=`echo $cont | grep -E -o "HTTP/1\.1 +$code"`
        html=`echo $cont | grep -E -o -i "$target"`
        if [[ -z $ok || -z $html ]] ; then
            echo "=============================="
            echo "GET $url FAILED!!!"
            echo "$ok"
            echo "$html"
            echo $cont
            echo "=============================="
            kill -SIGTERM $cow_pid
            exit 1
        fi
        sleep 0.3
    done
    echo "GET $url passed"
}

test_get $PROXY_ADDR/pac "apple.com" "noproxy" # test for pac
test_get google.com "</html>" # 301 redirect 
test_get www.google.com "</html>" # 302 redirect 
test_get www.reddit.com "</html>" # chunked encoding
test_get https://www.twitter.com "</html>" # builtin blocked site, HTTP CONNECT
test_get openvpn.net "</html>" # blocked site, all kinds of block method
test_get http://plan9.bell-labs.com/magic/man2html/1/2l "<head>" "" "404"

# Chinese sites may timeout on travis.
if [[ -z $TRAVIS ]]; then
    test_get www.wpxap.com "<html" # HTTP 1.0 server
    test_get youku.com "</html>" # 302 redirect
    test_get douban.com "</html>" # 301 redirect
    test_get www.taobao.com "<html>" # chunked encoding, weird can't tests for </html> in script
fi

kill -SIGTERM $cow_pid
exit 0
