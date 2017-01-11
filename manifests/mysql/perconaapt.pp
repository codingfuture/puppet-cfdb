#
# Copyright 2016-2017 (c) Andrey Galkin
#


class cfdb::mysql::perconaapt {
    assert_private()

    include cfsystem

    $lsbdistcodename = $::facts['lsbdistcodename']
    $percona_release = $::facts['operatingsystem'] ? {
        'Debian' => (versioncmp($::facts['operatingsystemrelease'], '9') >= 0) ? {
            true    => 'jessie',
            default => $lsbdistcodename
        },
        'Ubuntu' => (versioncmp($::facts['operatingsystemrelease'], '16.10') >= 0) ? {
            true    => 'yakkety',
            default => $lsbdistcodename
        },
        default  => $lsbdistcodename
    }

    apt::key {'percona-old':
        id      => '430BDF5C56E7C94E848EE60C1C4CBDCDCD2EFD2A',
        content => '
-----BEGIN PGP PUBLIC KEY BLOCK-----
Version: GnuPG v1

mQGiBEsm3aERBACyB1E9ixebIMRGtmD45c6c/wi2IVIa6O3G1f6cyHH4ump6ejOi
AX63hhEs4MUCGO7KnON1hpjuNN7MQZtGTJC0iX97X2Mk+IwB1KmBYN9sS/OqhA5C
itj2RAkug4PFHR9dy21v0flj66KjBS3GpuOadpcrZ/k0g7Zi6t7kDWV0hwCgxCa2
f/ESC2MN3q3j9hfMTBhhDCsD/3+iOxtDAUlPMIH50MdK5yqagdj8V/sxaHJ5u/zw
YQunRlhB9f9QUFfhfnjRn8wjeYasMARDctCde5nbx3Pc+nRIXoB4D1Z1ZxRzR/lb
7S4i8KRr9xhommFnDv/egkx+7X1aFp1f2wN2DQ4ecGF4EAAVHwFz8H4eQgsbLsa6
7DV3BACj1cBwCf8tckWsvFtQfCP4CiBB50Ku49MU2Nfwq7durfIiePF4IIYRDZgg
kHKSfP3oUZBGJx00BujtTobERraaV7lIRIwETZao76MqGt9K1uIqw4NT/jAbi9ce
rFaOmAkaujbcB11HYIyjtkAGq9mXxaVqCC3RPWGr+fqAx/akBLQ2UGVyY29uYSBN
eVNRTCBEZXZlbG9wbWVudCBUZWFtIDxteXNxbC1kZXZAcGVyY29uYS5jb20+iGAE
ExECACAFAksm3aECGwMGCwkIBwMCBBUCCAMEFgIDAQIeAQIXgAAKCRAcTL3NzS79
Kpk/AKCQKSEgwX9r8jR+6tAnCVpzyUFOQwCfX+fw3OAoYeFZB3eu2oT8OBTiVYu5
Ag0ESybdoRAIAKKUV8rbqlB8qwZdWlmrwQqg3o7OpoAJ53/QOIySDmqy5TmNEPLm
lHkwGqEqfbFYoTbOCEEJi2yFLg9UJCSBM/sfPaqb2jGP7fc0nZBgUBnFuA9USX72
O0PzVAF7rCnWaIz76iY+AMI6xKeRy91TxYo/yenF1nRSJ+rExwlPcHgI685GNuFG
chAExMTgbnoPx1ka1Vqbe6iza+FnJq3f4p9luGbZdSParGdlKhGqvVUJ3FLeLTqt
caOn5cN2ZsdakE07GzdSktVtdYPT5BNMKgOAxhXKy11IPLj2Z5C33iVYSXjpTelJ
b2qHvcg9XDMhmYJyE3O4AWFh2no3Jf4ypIcABA0IAJO8ms9ov6bFqFTqA0UW2gWQ
cKFN4Q6NPV6IW0rV61ONLUc0VFXvYDtwsRbUmUYkB/L/R9fHj4lRUDbGEQrLCoE+
/HyYvr2rxP94PT6Bkjk/aiCCPAKZRj5CFUKRpShfDIiow9qxtqv7yVd514Qqmjb4
eEihtcjltGAoS54+6C3lbjrHUQhLwPGqlAh8uZKzfSZq0C06kTxiEqsG6VDDYWy6
L7qaMwOqWdQtdekKiCk8w/FoovsMYED2qlWEt0i52G+0CjoRFx2zNsN3v4dWiIhk
ZSL00Mx+g3NA7pQ1Yo5Vhok034mP8L2fBLhhWaK3LG63jYvd0HLkUFhNG+xjkpeI
SQQYEQIACQUCSybdoQIbDAAKCRAcTL3NzS79KlacAJ9H6emL/8dsoquhE9PNnKCI
eMTmmQCfXRLIoNjJa20VEwJDzR7YVdBEiQI=
=AD5m
-----END PGP PUBLIC KEY BLOCK-----
',
        }

    apt::key {'percona':
        id      => '4D1BB29D63D98E422B2113B19334A25F8507EFA5',
        content => '
-----BEGIN PGP PUBLIC KEY BLOCK-----
Version: GnuPG v1

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
=5SzL
-----END PGP PUBLIC KEY BLOCK-----
',
        }

    apt::source { 'percona':
        location => $cfdb::mysql::percona_apt_repo,
        release  => $percona_release,
        repos    => 'main',
        pin      => $cfsystem::apt_pin + 1,
        require  => [
            Apt::Key['percona'],
            Apt::Key['percona-old'],
        ],
        notify   => Class['apt::update'],
    }

    package { 'percona-release': ensure => absent }
}
