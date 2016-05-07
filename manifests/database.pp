
define cfdb::database (
) {
    $title_split = $title.split('/')
    $cluster = $title_split[0]
    $database = $title_split[1]
    
    cfdb_database { $title:
        ensure => present,
        cluster => $cluster,
        database => $database,
    }
    
    cfdb::role { $title:
        cluster => $cluster,
        database => $database,
    }
}
