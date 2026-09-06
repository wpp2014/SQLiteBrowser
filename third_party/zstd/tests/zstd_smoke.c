#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include <zstd.h>

#define SMOKE_INPUT_SIZE 8192U
#define EXPECTED_ZSTD_VERSION_NUMBER 10507U
#define EXPECTED_ZSTD_VERSION_STRING "1.5.7"

static int check_zstd_result(const char *operation, size_t result)
{
    if (!ZSTD_isError(result)) {
        return 1;
    }

    fprintf(stderr, "%s failed: %s\n", operation, ZSTD_getErrorName(result));
    return 0;
}

static void fill_input(unsigned char *input, size_t input_size)
{
    static const char pattern[] =
        "SQLiteBrowser zstd shared-library smoke test payload.";
    size_t index;

    for (index = 0; index < input_size; ++index) {
        input[index] = (unsigned char)pattern[index % (sizeof(pattern) - 1U)];
    }
}

static int test_one_shot(const unsigned char *input, size_t input_size)
{
    const size_t compressed_capacity = ZSTD_compressBound(input_size);
    unsigned char *compressed = NULL;
    unsigned char *decoded = NULL;
    size_t compressed_size;
    size_t decoded_size;
    size_t expected_error;
    const char *error_name;
    int success = 0;

    compressed = (unsigned char *)malloc(compressed_capacity);
    decoded = (unsigned char *)malloc(input_size);
    if (compressed == NULL || decoded == NULL) {
        fprintf(stderr, "Unable to allocate one-shot smoke-test buffers.\n");
        goto cleanup;
    }

    compressed_size = ZSTD_compress(
        compressed,
        compressed_capacity,
        input,
        input_size,
        3
    );
    if (!check_zstd_result("ZSTD_compress", compressed_size)) {
        goto cleanup;
    }

    decoded_size = ZSTD_decompress(
        decoded,
        input_size,
        compressed,
        compressed_size
    );
    if (!check_zstd_result("ZSTD_decompress", decoded_size)) {
        goto cleanup;
    }

    if (decoded_size != input_size || memcmp(input, decoded, input_size) != 0) {
        fprintf(stderr, "One-shot compression round trip did not preserve the payload.\n");
        goto cleanup;
    }

    expected_error = ZSTD_decompress(
        decoded,
        input_size - 1U,
        compressed,
        compressed_size
    );
    if (!ZSTD_isError(expected_error)) {
        fprintf(stderr, "ZSTD_isError did not classify an undersized output buffer.\n");
        goto cleanup;
    }

    error_name = ZSTD_getErrorName(expected_error);
    if (error_name == NULL || error_name[0] == '\0') {
        fprintf(stderr, "ZSTD_getErrorName returned an empty error description.\n");
        goto cleanup;
    }

    success = 1;

cleanup:
    free(decoded);
    free(compressed);
    return success;
}

static int test_streaming(const unsigned char *input, size_t input_size)
{
    const size_t compressed_capacity =
        ZSTD_compressBound(input_size) + ZSTD_CStreamOutSize();
    const size_t decoded_capacity = input_size + ZSTD_DStreamOutSize();
    unsigned char *compressed = NULL;
    unsigned char *decoded = NULL;
    ZSTD_CStream *compression_stream = NULL;
    ZSTD_DStream *decompression_stream = NULL;
    ZSTD_inBuffer compression_input;
    ZSTD_outBuffer compression_output;
    ZSTD_inBuffer decompression_input;
    ZSTD_outBuffer decompression_output;
    size_t result;
    int success = 0;

    compressed = (unsigned char *)malloc(compressed_capacity);
    decoded = (unsigned char *)malloc(decoded_capacity);
    compression_stream = ZSTD_createCStream();
    decompression_stream = ZSTD_createDStream();
    if (compressed == NULL || decoded == NULL
            || compression_stream == NULL || decompression_stream == NULL) {
        fprintf(stderr, "Unable to allocate streaming smoke-test resources.\n");
        goto cleanup;
    }

    result = ZSTD_initCStream(compression_stream, 3);
    if (!check_zstd_result("ZSTD_initCStream", result)) {
        goto cleanup;
    }

    compression_input.src = input;
    compression_input.size = input_size;
    compression_input.pos = 0;
    compression_output.dst = compressed;
    compression_output.size = compressed_capacity;
    compression_output.pos = 0;

    while (compression_input.pos < compression_input.size) {
        const size_t previous_input_position = compression_input.pos;
        const size_t previous_output_position = compression_output.pos;

        result = ZSTD_compressStream2(
            compression_stream,
            &compression_output,
            &compression_input,
            ZSTD_e_continue
        );
        if (!check_zstd_result("ZSTD_compressStream2(ZSTD_e_continue)", result)) {
            goto cleanup;
        }
        if (compression_input.pos == previous_input_position
                && compression_output.pos == previous_output_position) {
            fprintf(stderr, "Streaming compression made no progress.\n");
            goto cleanup;
        }
        if (compression_output.pos == compression_output.size
                && compression_input.pos < compression_input.size) {
            fprintf(stderr, "Streaming compression exhausted its output buffer.\n");
            goto cleanup;
        }
    }

    do {
        result = ZSTD_compressStream2(
            compression_stream,
            &compression_output,
            &compression_input,
            ZSTD_e_end
        );
        if (!check_zstd_result("ZSTD_compressStream2(ZSTD_e_end)", result)) {
            goto cleanup;
        }
        if (result != 0U && compression_output.pos == compression_output.size) {
            fprintf(stderr, "Streaming compression could not finish the frame.\n");
            goto cleanup;
        }
    } while (result != 0U);

    result = ZSTD_initDStream(decompression_stream);
    if (!check_zstd_result("ZSTD_initDStream", result)) {
        goto cleanup;
    }

    decompression_input.src = compressed;
    decompression_input.size = compression_output.pos;
    decompression_input.pos = 0;
    decompression_output.dst = decoded;
    decompression_output.size = decoded_capacity;
    decompression_output.pos = 0;

    result = 1U;
    while (decompression_input.pos < decompression_input.size || result != 0U) {
        const size_t previous_input_position = decompression_input.pos;
        const size_t previous_output_position = decompression_output.pos;

        result = ZSTD_decompressStream(
            decompression_stream,
            &decompression_output,
            &decompression_input
        );
        if (!check_zstd_result("ZSTD_decompressStream", result)) {
            goto cleanup;
        }
        if (result == 0U && decompression_input.pos == decompression_input.size) {
            break;
        }
        if (decompression_input.pos == previous_input_position
                && decompression_output.pos == previous_output_position) {
            fprintf(stderr, "Streaming decompression made no progress.\n");
            goto cleanup;
        }
        if (decompression_output.pos == decompression_output.size) {
            fprintf(stderr, "Streaming decompression exhausted its output buffer.\n");
            goto cleanup;
        }
        if (decompression_input.pos == decompression_input.size && result != 0U) {
            fprintf(stderr, "Streaming decompression ended with an incomplete frame.\n");
            goto cleanup;
        }
    }

    if (result != 0U
            || decompression_output.pos != input_size
            || memcmp(input, decoded, input_size) != 0) {
        fprintf(stderr, "Streaming compression round trip did not preserve the payload.\n");
        goto cleanup;
    }

    success = 1;

cleanup:
    ZSTD_freeDStream(decompression_stream);
    ZSTD_freeCStream(compression_stream);
    free(decoded);
    free(compressed);
    return success;
}

int main(void)
{
    unsigned char input[SMOKE_INPUT_SIZE];
    const unsigned int version_number = ZSTD_versionNumber();
    const char *version_string = ZSTD_versionString();

    if (version_number != EXPECTED_ZSTD_VERSION_NUMBER
            || version_string == NULL
            || strcmp(version_string, EXPECTED_ZSTD_VERSION_STRING) != 0) {
        fprintf(
            stderr,
            "Unexpected zstd version: number=%u string=%s\n",
            version_number,
            version_string != NULL ? version_string : "(null)"
        );
        return EXIT_FAILURE;
    }

    fill_input(input, sizeof(input));

    if (!test_one_shot(input, sizeof(input))) {
        return EXIT_FAILURE;
    }

    if (!test_streaming(input, sizeof(input))) {
        return EXIT_FAILURE;
    }

    printf("zstd %s shared-library smoke test passed.\n", version_string);
    return EXIT_SUCCESS;
}
