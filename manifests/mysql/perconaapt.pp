
class cfdb::mysql::perconaapt {
    assert_private()
    
    include cfsystem
    
    case $::facts['lsbdistcodename'] {
        'xenial', 'yakkety': {
            $percona_release = 'wily'
        }
        'stretch': {
            $percona_release = 'jessie'
        }
        default: {
            $percona_release = $::facts['lsbdistcodename']
        }
    }
    
    apt::key {'percona':
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
    
    apt::source { 'percona':
        location => $cfdb::mysql::percona_apt_repo,
        release  => $percona_release,
        repos    => 'main',
        pin      => $cfsystem::apt_pin + 1,
        require  => Apt::Key['percona'],
        notify   => Class['apt::update'],
    }

    package { 'percona-release': ensure => absent }
}
