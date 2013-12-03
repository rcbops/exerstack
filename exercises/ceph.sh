#!/usr/bin/env bash

function setup(){
  POOL_NAME="exerstack_tests"
  OBJ_FILE=$(tempfile)
  dd if=/dev/urandom of=$OBJ_FILE bs=1M count=10
  dd if=/dev/urandom of=$OBJ_FILE.modified bs=1M count=10
}

includes(){
    stdin=$(cat -)
    regex="$1"
    if [[ "$stdin" =~ $regex ]]; then
        return 0
    else
        return 1
    fi
}
not_includes(){
    stdin=$(cat -)
    regex="$1"
    if [[ ! "$stdin" =~ $regex ]]; then
        return 0
    else
        return 1
    fi
}

# The rbd command can only import files to images, it can't modify the
# contents of existing images. This function allows an image to be modified 
# without using rbd-fuse or a kernel mapping.
# NOTE: No error handling, file size must be <= image size. If file is smaller
# than image then only len(file) of the image will be overwritten.
function rbdwrite(){
    image_name="$1"
    file_name="$2"

    python - "$image_name" "$file_name" <<EOPYTHON
import sys
import rados
import rbd

rbd_image_name=sys.argv[1]
file_name=sys.argv[2]

rados_client=rados.Rados(rados_id='admin',conffile='/etc/ceph/ceph.conf')
rados_client.connect()
pool=rados_client.open_ioctx('rbd')
rbd_image=rbd.Image(pool,rbd_image_name)
file_handle=open(file_name,'rb')
chunk_size=(1024**2)*4

while True:
    chunk_start_offset=file_handle.tell()
    chunk = file_handle.read(chunk_size)
    sys.stdout.flush()
    if len(chunk) == 0:
        break
    else:
        rbd_image.write(chunk, chunk_start_offset)
file_handle.close()
rbd_image.close()
pool.close()

EOPYTHON
}

function 000_test_includes(){
    echo "abc" |includes abc
    echo "def" |not_includes abc
    echo -n    |not_includes abc
}

function 001_ceph_health(){
    ceph health |includes HEALTH_OK
}

function 002_ceph_status(){
    ceph status |includes HEALTH_OK
    ceph status |includes quorum

    # Monitor epoch should be greater than 0
    [[ $(ceph status |sed -n 's/.*election epoch \([0-9]\+\).*/\1/p') -gt 0 ]]

}

function 010_osd_tree(){
    result=0
    output="$(ceph osd tree)"
    grep -q '# id	weight	type name	up/down	reweight' <<<"$output"
    grep -q '[-]1.*root default' <<<"$output"
    grep -q 'osd.0	up' <<<"$output"
}

function 020_rados_create_pool(){
    rados lspools |includes $POOL_NAME\
        && rados rmpool $POOL_NAME $POOL_NAME --yes-i-really-really-mean-it
    rados mkpool $POOL_NAME
    rados lspools | includes $POOL_NAME
}

function 030_rados_ls_pools(){
    rados lspools |includes $POOL_NAME
}

function 040_rados_put_object(){
    result=0
    rados -p $POOL_NAME put object $OBJ_FILE
    rados -p $POOL_NAME ls |includes object
    rados -p $POOL_NAME get object $OBJ_FILE.downloaded
    diff $OBJ_FILE $OBJ_FILE.downloaded
}

function 050_rados_list_objects(){
    rados -p $POOL_NAME ls|includes object
}

function 060_rados_get_object(){
    rados -p $POOL_NAME ls|includes object
    rados -p $POOL_NAME get object $OBJ_FILE.downloaded
    diff $OBJ_FILE $OBJ_FILE.downloaded
}

function 061_rados_cp_object(){
    rados -p $POOL_NAME ls|includes object
    rados -p $POOL_NAME cp object object_copy
    rados -p $POOL_NAME ls|includes object
    rados -p $POOL_NAME ls|includes object_copy
    rm $OBJ_FILE.downloaded||:
    rados -p $POOL_NAME get object_copy $OBJ_FILE.downloaded
    diff $OBJ_FILE $OBJ_FILE.downloaded
    rados -p $POOL_NAME rm object_copy
    rados -p $POOL_NAME ls|not_includes object_copy
}

function 062_rados_pool_snapshot(){
    rados -p $POOL_NAME ls|includes object
    rados -p $POOL_NAME mksnap test_snap
    rados -p $POOL_NAME lssnap |includes test_snap
    rados -p $POOL_NAME rm object
    rados -p $POOL_NAME ls |not_includes object
    rados -p $POOL_NAME rollback object test_snap
    rados -p $POOL_NAME ls|includes object
    rm $OBJ_FILE.downloaded||:
    rados -p $POOL_NAME get object $OBJ_FILE.downloaded
    diff $OBJ_FILE $OBJ_FILE.downloaded
}


function 070_rados_delete_object(){
    rados -p $POOL_NAME ls|includes object
    rados -p $POOL_NAME rm object
    rados -p $POOL_NAME ls|not_includes object
}

function 080_rados_delete_pool(){
    rados lspools |includes $POOL_NAME
    rados rmpool $POOL_NAME $POOL_NAME --yes-i-really-really-mean-it
    rados lspools |not_includes $POOL_NAME
    rados mkpool $POOL_NAME
    rados lspools |includes $POOL_NAME
    040_rados_put_object
}

function 090_initalise_rbd_directory(){
    # When the first rbd image is created in a pool the rbd_directory object
    # is also created. Without this object rbd lists fail.
    rados -p rbd ls | includes rbd_directory && rados -p rbd rm rbd_directory||:
    rados -p rbd ls | includes rbd_children && rados -p rbd rm rbd_children ||:

    rbd create temp --image-format 2 --size 20
    rbd rm temp
}

function 091_rbd_create_image(){
    rbd ls |includes test_image && rbd rm test_image
    rbd create test_image --size 1024 --image-format 2
    rbd ls |includes test_image
}
function 092_rbd_image_delete(){
    rbd ls |includes test_image
    rbd rm test_image
    rbd ls |not_includes test_image
    rbd create test_image --size 1024 --image-format 2
}

function 100_rbd_list_images(){
    rbd ls |includes test_image
}
function 101_rbd_info(){
    output=$(rbd info test_image)
    grep -q 'size [0-9]* [KMGTPE]B in [0-9]* objects'<<<"$output"
    grep -q 'order [0-9]* ([0-9]* KB objects)'<<<"$output"
    grep -q 'block_name_prefix:'<<<"$output"
    grep -q 'format: 2'<<<"$output"
}

function 120_rbd_image_import_export(){
    rbd ls |includes test_image && rbd rm test_image
    rbd import $OBJ_FILE test_image --image-format 2
    [ -f $OBJ_FILE.downloaded ] && rm $OBJ_FILE.downloaded
    rbd export test_image $OBJ_FILE.downloaded
    diff $OBJ_FILE $OBJ_FILE.downloaded
    [ -f $OBJ_FILE.downloaded ] && rm $OBJ_FILE.downloaded
}

function 130_rbd_snapshot_create(){
    rbd ls |includes test_image && rbd rm test_image
    rbd import $OBJ_FILE test_image --image-format 2
    rbd snap create test_image@test_snap
    rbd snap ls test_image |includes test_snap

    rm $OBJ_FILE.downloaded||:
    rbd export test_image@test_snap $OBJ_FILE.downloaded
    diff $OBJ_FILE $OBJ_FILE.downloaded
}

function 140_rbd_snapshot_modify_original(){
    rbd snap ls test_image |includes test_snap
    rbdwrite test_image $OBJ_FILE.modified
    rm $OBJ_FILE.downloaded||:
    rbd export test_image $OBJ_FILE.downloaded
    diff $OBJ_FILE.downloaded $OBJ_FILE.modified
    rm $OBJ_FILE.downloaded||:
    rbd export test_image@test_snap $OBJ_FILE.downloaded
    diff $OBJ_FILE.downloaded $OBJ_FILE
}

function 150_rbd_snapshot_rollback(){
    rbd snap ls test_image |includes test_snap
    rbd snap rollback test_image@test_snap
    rm $OBJ_FILE.downloaded||:
    rbd export test_image@test_snap $OBJ_FILE.downloaded
    diff $OBJ_FILE.downloaded $OBJ_FILE
}

function 155_rbd_clone(){
    # Test that clones contain a correct copy of source image.
    rbd snap ls test_image | includes test_snap
    rbd snap protect test_image@test_snap
    rbd clone test_image@test_snap test_image_clone
    rm $OBJ_FILE.downloaded||:
    rbd export test_image_clone $OBJ_FILE.downloaded
    diff $OBJ_FILE $OBJ_FILE.downloaded

}

function 160_rbd_clone_independant_modification(){
    # Test that clone source and destination can be modified independantly.
    # At start test_image and test_clone contain contennts of $OBJ_FILE

    # Snap must exist.
    rbd snap ls test_image | includes test_snap


    # Modify original, check clone statys consistent
    rbdwrite test_image $OBJ_FILE.modified
    rm $OBJ_FILE.downloaded||:
    rbd export test_image_clone $OBJ_FILE.downloaded
    diff $OBJ_FILE $OBJ_FILE.downloaded
    rm $OBJ_FILE.downloaded||:
    rbd export test_image $OBJ_FILE.downloaded
    diff $OBJ_FILE.modified $OBJ_FILE.downloaded

    # Reset test_image to contents of $OBJ_FILE and check.
    rbd snap rollback test_image@test_snap
    rm $OBJ_FILE.downloaded||:
    rbd export test_image $OBJ_FILE.downloaded
    diff $OBJ_FILE $OBJ_FILE.downloaded

    # Modify clone, check original statys consistent
    rbdwrite test_image_clone $OBJ_FILE.modified
    rm $OBJ_FILE.downloaded||:
    rbd export test_image_clone $OBJ_FILE.downloaded
    diff $OBJ_FILE.modified $OBJ_FILE.downloaded
    rm $OBJ_FILE.downloaded||:
    rbd export test_image $OBJ_FILE.downloaded
    diff $OBJ_FILE $OBJ_FILE.downloaded

    # Cleanup clone
    # Important to unprotect snapshot when clone is removed so snapshot can
    # be removed later on.
    rbd rm test_image_clone
    rbd ls |not_includes test_image_clone
    rbd snap rollback test_image@test_snap
    rbd snap unprotect test_image@test_snap
}

function 165_rbd_snapshot_remove(){
    rbd snap ls test_image |includes test_snap
    rbd snap rm test_image@test_snap
    rbd snap ls test_image |not_includes test_snap
}

function 170_rbd_copy(){
    rbd cp test_image test_image_copy
    rbd ls |includes test_image_copy
    rm $OBJ_FILE.downloaded||:
    rbd export test_image_copy $OBJ_FILE.downloaded
    diff $OBJ_FILE $OBJ_FILE.downloaded
    rbd rm test_image_copy
    rbd ls |not_includes test_image_copy
}

function 180_rbd_rename(){
    rbd ls |includes test_image
    rbd ls |not_includes test_image_rename
    rbd mv test_image test_image_rename
    rbd ls |not_includes 'test_image$'
    rbd ls |includes test_image_rename

    rm $OBJ_FILE.downloaded||:
    rbd export test_image_rename $OBJ_FILE.downloaded
    diff $OBJ_FILE $OBJ_FILE.downloaded
    rbd mv  test_image_rename test_image
    rbd ls |includes test_image
    rbd ls |not_includes test_image_rename
}

function 200_ceph_pg_stat(){
    ceph pg stat |includes 'active\+clean'
}

function 210_ceph_quorum_status(){
    ceph quorum_status |includes election_epoc
}

function 220_rados_setxattr(){
    rados -p $POOL_NAME ls |includes object
    rados -p $POOL_NAME listxattr object |not_includes attr
    rados -p $POOL_NAME setxattr object attr value
    rados -p $POOL_NAME getxattr object attr|includes value
}

function 230_rados_list_xattr(){
    rados -p $POOL_NAME listxattr object |includes attr
}

function 240_rados_get_xattr(){
    rados -p $POOL_NAME listxattr object |includes attr
    rados -p $POOL_NAME getxattr object attr|includes value
}

function 250_rados_rm_xattr(){
    rados -p $POOL_NAME listxattr object |includes attr
    rados -p $POOL_NAME rmxattr object attr
    rados -p $POOL_NAME listxattr object |not_includes attr
}

function 260_rados_list_watchers(){
    [[ -z "$(rados -p $POOL_NAME listwatchers object)" ]]
}

function 270_rados_setomapval(){
    rados -p $POOL_NAME ls |includes object
    rados -p $POOL_NAME listomapvals object |not_includes attr
    rados -p $POOL_NAME setomapval object attr value
    rados -p $POOL_NAME getomapval object attr|includes value
}
function 280_rados_list_omap(){
    rados -p $POOL_NAME listomapvals object |includes attr
}

function 290_rados_get_omap(){
    rados -p $POOL_NAME listomapvals object |includes attr
    rados -p $POOL_NAME getomapval object attr|includes value
}

function 300_rados_rm_omap(){
    rados -p $POOL_NAME listomapvals object |includes attr
    rados -p $POOL_NAME rmomapkey object attr
    rados -p $POOL_NAME listomapvals object |not_includes attr
}

function 310_rados_cp_pool(){
    rados mkpool ${POOL_NAME}_cp
    rados cppool $POOL_NAME ${POOL_NAME}_cp
    rados -p ${POOL_NAME}_cp ls |includes object
    rm $OBJ_FILE.downloaded ||:
    rados -p ${POOL_NAME}_cp get object $OBJ_FILE.downloaded
    diff $OBJ_FILE $OBJ_FILE.downloaded
    rados rmpool ${POOL_NAME}_cp ${POOL_NAME}_cp --yes-i-really-really-mean-it
    rados lspools |not_includes ${POOL_NAME}_cp
}

function 320_rados_df(){
    rados -p $POOL_NAME ls |includes object

    # Col 4 = number of objects. There should be one object in the test pool
    [[ "$(rados df |awk '/'$POOL_NAME'/{print $4}')" == "1" ]]
}

function 330_ceph_scrub(){
    ceph scrub
}

function 340_ceph_report(){
    ceph report |python -m json.tool
}

function 350_ceph_pg_dump_pools_json(){
    ceph pg dump_pools_json |python -m json.tool
}

function 260_ceph_osd_stat(){
    read _ _ _ osds _ in _ < <(ceph osd stat)
    [[ "$osds" == "$in" ]]
}

#function 999_rados_pg_num_expand(){
#    rados mkpool pg_test
#    pgnum=$(ceph osd pool get pg_test pg_num |cut -d' ' -f2)
#    pg_num_target=$(($pgnum * 2 ))
#    rados -p pg_test put object $OBJ_FILE
#    ceph osd pool set pg_test pg_num $pg_num_target
#    ceph osd pool set pg_test pgp_num $pg_num_target
#    for i in {1..240};do
#        [[ $pg_num_target == $(ceph osd pool get $1 pg_num |cut -d' ' -f2) ]]\
#            && [[ $pg_num_target == $(ceph osd pool get $1 pgp_num |cut -d' ' -f2) ]]\
#                && break
#        sleep 1
#    done
#    rm $OBJ_FILE.downloaded||:
#    rados -p pg_test get object $OBJ_FILE.downloaded
#    diff $OBJ_FILE $OBJ_FILE.downloaded
#    rados rmpool pg_test pg_test --yes-i-really-really-mean-it
#    rados lspools |not_includes pg_test
#
#}

function teardown(){
    [ -f $OBJ_FILE ] && rm -rf $OBJ_FILE
    [ -f ${OBJ_FILE}.downloaded ] && rm -rf ${OBJ_FILE}.downloaded
    [ -f ${OBJ_FILE}.modified ] && rm -rf ${OBJ_FILE}.modified
    rbd rm test_clone
    rbd snap rm test_snap
    rbd unprotect test_image@test_snap
    rbd rm test_image
    rbd rm test_image_copy ||:
    rbd rm test_image_clone ||:
    rbd rm test_image_rename ||:

    rbd ls|while read image; do 
        rbd snap ls $image |awk '/^SNAP/{next}; {print $2}'|while read snap; do 
            rbd snap unprotect $image@$snap;
            rbd snap rm $image@$snap
        done
    done
    lspools |grep -q $POOL_NAME\
        && rados rmpool $POOL_NAME $POOL_NAME --yes-i-really-really-mean-it
}
