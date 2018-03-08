#!/bin/dash

set -e

mode=$1
shift

export ES_PATH_CONF=/etc/elasticsearch
elastic_root="/usr/share/elasticsearch"
plugin_root="${elastic_root}/plugins"
pt="${elastic_root}/bin/elasticsearch-plugin"
ever=$(dpkg-query -W --showformat '${Version}' elasticsearch)
res=0

for p in "$@" skip; do
    if [ $p = "skip" ]; then
        continue;
    fi

    n=$(echo $p | cut -d: -f1)
    i=$(echo "$p:$p" | cut -d: -f2)
    s="${plugin_root}/${n}/${ever}.stamp"

    if [ ! -d "${plugin_root}/${n}" ]; then
        if [ $mode = 'install' ]; then
            $pt install $i
            touch /db/elasticsearch_*/conf/restart_required
            touch $s
        else
            res=1
        fi
    elif [ ! -f $s ]; then
        if [ $mode = 'install' ]; then
            $pt remove $n
            $pt install $i
            touch /db/elasticsearch_*/conf/restart_required
            touch $s
        else
            res=1
        fi
    fi
done

exit $res
