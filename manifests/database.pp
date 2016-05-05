
class cfdb::database (
    $title,
) {
    $title_split = $title.split('/')
    $cluster_name = $title_split[0]
    $db_name = $title_split[1]
    
    cfdb_database { $title:
        cluster_name => $cluster_name,
        db_name => $db_name,
    }
}
