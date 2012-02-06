function setup() {
    # Remove old certificates
    rm -f cacert.pem
    rm -f cert.pem
    rm -f pk.pem
}

function 001_get_certificates() {
    # Get Certificates
    nova x509-get-root-cert
    nova x509-create-cert
}

function 002_register_bundle() {
    # Max time to wait for image to be registered
    REGISTER_TIMEOUT=${REGISTER_TIMEOUT:-15}

    BUCKET=testbucket
    IMAGE=bundle.img
    truncate -s 5M ${TMPDIR}/$IMAGE
    euca-bundle-image -i ${TMPDIR}/$IMAGE

    euca-upload-bundle -b $BUCKET -m ${TMPDIR}/$IMAGE.manifest.xml


    AMI=`euca-register $BUCKET/$IMAGE.manifest.xml | cut -f2`

    # Wait for the image to become available
    if ! timeout $REGISTER_TIMEOUT sh -c "while euca-describe-images | grep '$AMI' | grep 'available'; do sleep 1; done"; then
        echo "Image $AMI not available within $REGISTER_TIMEOUT seconds"
        exit 1
    fi
}


