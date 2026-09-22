# Writes MENDER_ARTIFACT_NAME into /etc/motd, so that two builds which differ
# only in their artifact name also differ on the device.
#
# ROOTFS_POSTPROCESS_COMMAND takes function names, not shell, which is why
# this is a class rather than a few lines in a kas file.

artifact_motd() {
	printf 'Mender image - %s\n' "${MENDER_ARTIFACT_NAME}" > ${IMAGE_ROOTFS}/etc/motd
}

ROOTFS_POSTPROCESS_COMMAND += "artifact_motd"
