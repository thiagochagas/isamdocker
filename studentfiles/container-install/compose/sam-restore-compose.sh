#!/bin/bash

# Set file locations
PROJECT="`dirname \"$0\"`"         # relative
PROJECT="`( cd \"$PROJECT/iamlab\" && pwd )`"  # absolutized and normalized
if [ -z "$PROJECT" ] ; then
  echo "Failed to get local path"
  exit 1  # fail
fi
YAML=${PROJECT}/docker-compose.yaml

# Create a temporary working directory
TMPDIR=/tmp/backup-$RANDOM$RANDOM
mkdir $TMPDIR

if [ $# -ne 1 ]
then
  echo "Usage: $0 <archive file>"
  exit 1
fi

if [ ! -f "$1" ]
then
  echo "File not found - $1"
  exit 1
fi

# Unpack archive to temporary directory
tar -xf $1 -C $TMPDIR

# CD to compose project to pick up .env
cd ${PROJECT}

# Get docker container ID for openldap container
OPENLDAP="$(docker-compose -f ${YAML} ps -q openldap)"

# Restore LDAP Data to OpenLDAP
docker cp ${TMPDIR}/secauthority.ldif ${OPENLDAP}:/tmp/secauthority.ldif
docker exec -- ${OPENLDAP} ldapadd -c -f /tmp/secauthority.ldif -H "ldaps://localhost:636" -D "cn=root,secAuthority=Default" -w "Passw0rd"
docker cp ${TMPDIR}/ibmcom.ldif ${OPENLDAP}:/tmp/ibmcom.ldif
docker exec -- ${OPENLDAP} ldapadd -c -f /tmp/ibmcom.ldif -H "ldaps://localhost:636" -D "cn=root,secAuthority=Default" -w "Passw0rd"
docker exec -- ${OPENLDAP} rm /tmp/secauthority.ldif
docker exec -- ${OPENLDAP} rm /tmp/ibmcom.ldif

# Get docker container ID for postgresql container
POSTGRESQL="$(docker-compose -f ${YAML} ps -q postgresql)"

# Restore DB
docker exec -i -- ${POSTGRESQL} /usr/local/bin/psql isam < ${TMPDIR}/isam.db

# Get docker container ID for isamconfig container
ISAMCONFIG="$(docker-compose -f ${YAML} ps -q isamconfig)"

# Copy snapshots to the isamconfig container
SNAPSHOTS=`ls ${TMPDIR}/*.snapshot`
for SNAPSHOT in $SNAPSHOTS; do
docker cp ${SNAPSHOT} ${ISAMCONFIG}:/var/shared/snapshots
done

rm -rf $TMPDIR

# Restart environment to apply updated files
docker-compose -f ${YAML} restart

echo Done.
