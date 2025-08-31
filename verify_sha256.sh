#!/bin/bash
# verify_sha256.sh: Verifies SHA256 checksum of a file against a checksum file.
# Purpose: Ensure integrity of Debian Bookworm netinst ISO for Phase 1 VM setup.
# Usage: ./verify_sha256.sh <file_to_verify> <checksum_file>
# Example: ./verify_sha256.sh debian-12.7.0-amd64-netinst.iso SHA256SUMS
# Breadcrumb: [PHASE1_SHA256_VERIFY_20250827] Script for SHA256 verification on macOS.
# Requirements: macOS (Sonoma), shasum (built-in), SHA256SUMS from debian.org.
# Notes: Idempotent, exits on error, logs to stdout.

# Exit on error
set -e

# Variables (parameterized for replicability)
FILE_TO_VERIFY="$1"  # File to check (e.g., debian-12.7.0-amd64-netinst.iso)
CHECKSUM_FILE="$2"   # Checksum file (e.g., SHA256SUMS)

# Check if arguments are provided
if [ -z "$FILE_TO_VERIFY" ] || [ -z "$CHECKSUM_FILE" ]; then
    echo "Error: Missing arguments."
    echo "Usage: $0 <file_to_verify> <checksum_file>"
    exit 1
fi

# Check if files exist
if [ ! -f "$FILE_TO_VERIFY" ]; then
    echo "Error: File '$FILE_TO_VERIFY' not found."
    exit 1
fi
if [ ! -f "$CHECKSUM_FILE" ]; then
    echo "Error: Checksum file '$CHECKSUM_FILE' not found."
    exit 1
fi

# Calculate SHA256 sum of the file
CALCULATED_SUM=$(shasum -a 256 "$FILE_TO_VERIFY" | awk '{print $1}')
echo "Calculated SHA256: $CALCULATED_SUM"

# Extract expected SHA256 sum from checksum file
EXPECTED_SUM=$(grep "$(basename "$FILE_TO_VERIFY")" "$CHECKSUM_FILE" | awk '{print $1}')
if [ -z "$EXPECTED_SUM" ]; then
    echo "Error: No SHA256 sum found for '$FILE_TO_VERIFY' in '$CHECKSUM_FILE'."
    exit 1
fi
echo "Expected SHA256: $EXPECTED_SUM"

# Compare sums
if [ "$CALCULATED_SUM" = "$EXPECTED_SUM" ]; then
    echo "Success: SHA256 checksums match for '$FILE_TO_VERIFY'."
    exit 0
else
    echo "Error: SHA256 checksums do not match for '$FILE_TO_VERIFY'."
    echo "Calculated: $CALCULATED_SUM"
    echo "Expected: $EXPECTED_SUM"
    exit 1
fi
