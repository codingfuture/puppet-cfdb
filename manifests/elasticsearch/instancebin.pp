#
# Copyright 2018 (c) Andrey Galkin
#


define cfdb::elasticsearch::instancebin(
    String[1] $cluster,
    String[1] $user,
    String[1] $root_dir,
    String[1] $service_name,
    String[1] $version,
    Boolean $is_cluster,
    Boolean $is_arbitrator,
    Boolean $is_primary,
    Hash $settings_tune,
    Hash[String[1], Variant[
        Struct[{
            type       => Enum['cleanup_old'],
            prefix     => String[1],
            timestring => Optional[String[1]],
            unit       => Optional[String[1]],
            unit_count => Optional[Numeric],
            cron       => Optional[Hash],
        }],
        Struct[{
            actions => Hash,
            cron       => Optional[Hash],
        }],
    ]] $sched_actions,
){
    assert_private()

    $conf_dir = "${root_dir}/conf"

    #---

    file { "${cfdb::bin_dir}/cfdb_${cluster}_curl":
        mode    => '0755',
        content => epp('cfdb/cfdb_curl.epp', {
            user => $user,
        }),
    }

    file { "${root_dir}/bin/cfdb_curl":
        owner   => $user,
        mode    => '0750',
        content => '#!/bin/false',
        replace => false,
    }

    #---

    file { "${conf_dir}/ingest-geoip":
        owner   => $user,
        mode    => '0750',
        source  => '/etc/elasticsearch/ingest-geoip',
        recurse => true,
    }

    #---

    include cfdb::elasticsearch::curator

    $curator_cmd = "${cfdb::bin_dir}/cfdb_${cluster}_curator"

    file { $curator_cmd:
        mode    => '0755',
        content => epp('cfdb/cfdb_curator.epp', {
            user => $user,
        }),
    }

    $curator_dir = "${root_dir}/.curator"

    file { $curator_dir:
        ensure => directory,
        owner  => $user,
        group  => $user,
        mode   => '0750',
    }
    file { "${curator_dir}/curator.yml":
        owner   => $user,
        group   => $user,
        mode    => '0640',
        content => to_yaml({
            client => {
                hosts => [ pick($settings_tune['cfdb']['listen'], '127.0.0.1') ],
                port  => $settings_tune['cfdb']['port'],
            }
        }),
    }

    #---
    $sched_actions.each | $name, $inp_cfg | {
        if $inp_cfg['type'] == 'cleanup_old' {
            $cfg = {
                actions => {
                    '1' => {
                        action => delete_indices,
                        options => {
                            ignore_empty_list => true,
                        },
                        filters => [
                            {
                                filtertype => pattern,
                                kind => prefix,
                                value => "${inp_cfg['prefix']}-",
                            },
                            {
                                filtertype => age,
                                source => name,
                                direction => older,
                                timestring => pick($inp_cfg['timestring'], '%Y.%m.%d'),
                                unit => pick($inp_cfg['unit'], 'days'),
                                unit_count => pick($inp_cfg['unit_count'], 30),
                            },
                        ],
                    }
                }
            }
        } else {
            $cfg = {
                actions => $inp_cfg['actions']
            }
        }

        $action_file = "${curator_dir}/act_${name}.yml"

        file { $action_file:
            owner   => $user,
            group   => $user,
            mode    => '0640',
            content => to_yaml($cfg),
        }

        if $is_primary {
            create_resources(
                cron,
                {
                    "cfdb-schedact-${title}-${name}" => merge(
                        pick( $inp_cfg['cron'], {} ),
                        { command => "${curator_cmd} ${action_file}" }
                    ),
                },
                {
                    hour => 2,
                    minute => 10,
                }
            )
        }
    }
}
