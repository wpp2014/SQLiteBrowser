#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include <brotli/decode.h>
#include <brotli/encode.h>

#define SMOKE_INPUT_SIZE 8192U
#define EXPECTED_BROTLI_VERSION 0x01002000U

static void fill_input(uint8_t *input, size_t input_size)
{
    static const char pattern[] =
        "SQLiteBrowser Brotli shared-library smoke test payload.";
    size_t index;

    for (index = 0; index < input_size; ++index) {
        input[index] = (uint8_t)pattern[index % (sizeof(pattern) - 1U)];
    }
}

static int test_one_shot(const uint8_t *input, size_t input_size)
{
    const size_t compressed_capacity = BrotliEncoderMaxCompressedSize(input_size);
    uint8_t *compressed = NULL;
    uint8_t *decoded = NULL;
    size_t compressed_size = compressed_capacity;
    size_t decoded_size = input_size;
    int success = 0;

    compressed = (uint8_t *)malloc(compressed_capacity);
    decoded = (uint8_t *)malloc(input_size);
    if (compressed == NULL || decoded == NULL) {
        fprintf(stderr, "Unable to allocate one-shot smoke-test buffers.\n");
        goto cleanup;
    }

    if (BrotliEncoderCompress(
            BROTLI_DEFAULT_QUALITY,
            BROTLI_DEFAULT_WINDOW,
            BROTLI_MODE_GENERIC,
            input_size,
            input,
            &compressed_size,
            compressed) != BROTLI_TRUE) {
        fprintf(stderr, "BrotliEncoderCompress failed.\n");
        goto cleanup;
    }

    if (BrotliDecoderDecompress(
            compressed_size,
            compressed,
            &decoded_size,
            decoded) != BROTLI_DECODER_RESULT_SUCCESS) {
        fprintf(stderr, "BrotliDecoderDecompress failed.\n");
        goto cleanup;
    }

    if (decoded_size != input_size || memcmp(input, decoded, input_size) != 0) {
        fprintf(stderr, "One-shot compression round trip did not preserve the payload.\n");
        goto cleanup;
    }

    success = 1;

cleanup:
    free(decoded);
    free(compressed);
    return success;
}

static int test_streaming(const uint8_t *input, size_t input_size)
{
    const size_t compressed_capacity =
        BrotliEncoderMaxCompressedSize(input_size) + 1024U;
    uint8_t *compressed = NULL;
    uint8_t *decoded = NULL;
    BrotliEncoderState *encoder = NULL;
    BrotliDecoderState *decoder = NULL;
    const uint8_t *next_input = input;
    uint8_t *next_output;
    size_t available_input = input_size;
    size_t available_output;
    size_t total_output = 0U;
    size_t compressed_size;
    BrotliDecoderResult decoder_result = BROTLI_DECODER_RESULT_NEEDS_MORE_INPUT;
    int success = 0;

    compressed = (uint8_t *)malloc(compressed_capacity);
    decoded = (uint8_t *)malloc(input_size);
    encoder = BrotliEncoderCreateInstance(NULL, NULL, NULL);
    decoder = BrotliDecoderCreateInstance(NULL, NULL, NULL);
    if (compressed == NULL || decoded == NULL || encoder == NULL || decoder == NULL) {
        fprintf(stderr, "Unable to allocate streaming smoke-test resources.\n");
        goto cleanup;
    }

    next_output = compressed;
    available_output = compressed_capacity;
    while (BrotliEncoderIsFinished(encoder) != BROTLI_TRUE) {
        const size_t previous_input = available_input;
        const size_t previous_output = available_output;

        if (BrotliEncoderCompressStream(
                encoder,
                BROTLI_OPERATION_FINISH,
                &available_input,
                &next_input,
                &available_output,
                &next_output,
                &total_output) != BROTLI_TRUE) {
            fprintf(stderr, "BrotliEncoderCompressStream failed.\n");
            goto cleanup;
        }

        if (available_input == previous_input && available_output == previous_output
                && BrotliEncoderHasMoreOutput(encoder) != BROTLI_TRUE) {
            fprintf(stderr, "Streaming compression made no progress.\n");
            goto cleanup;
        }

        if (available_output == 0U && BrotliEncoderIsFinished(encoder) != BROTLI_TRUE) {
            fprintf(stderr, "Streaming compression exhausted its output buffer.\n");
            goto cleanup;
        }
    }

    compressed_size = compressed_capacity - available_output;
    next_input = compressed;
    available_input = compressed_size;
    next_output = decoded;
    available_output = input_size;
    total_output = 0U;

    do {
        const size_t previous_input = available_input;
        const size_t previous_output = available_output;

        decoder_result = BrotliDecoderDecompressStream(
            decoder,
            &available_input,
            &next_input,
            &available_output,
            &next_output,
            &total_output
        );

        if (decoder_result == BROTLI_DECODER_RESULT_ERROR) {
            const BrotliDecoderErrorCode error_code = BrotliDecoderGetErrorCode(decoder);
            fprintf(
                stderr,
                "BrotliDecoderDecompressStream failed: %s\n",
                BrotliDecoderErrorString(error_code)
            );
            goto cleanup;
        }

        if (decoder_result != BROTLI_DECODER_RESULT_SUCCESS
                && available_input == previous_input
                && available_output == previous_output) {
            fprintf(stderr, "Streaming decompression made no progress.\n");
            goto cleanup;
        }

        if (decoder_result == BROTLI_DECODER_RESULT_NEEDS_MORE_OUTPUT
                && available_output == 0U) {
            fprintf(stderr, "Streaming decompression exhausted its output buffer.\n");
            goto cleanup;
        }

        if (decoder_result == BROTLI_DECODER_RESULT_NEEDS_MORE_INPUT
                && available_input == 0U) {
            fprintf(stderr, "Streaming decompression ended with an incomplete stream.\n");
            goto cleanup;
        }
    } while (decoder_result != BROTLI_DECODER_RESULT_SUCCESS);

    if (BrotliDecoderIsFinished(decoder) != BROTLI_TRUE
            || total_output != input_size
            || memcmp(input, decoded, input_size) != 0) {
        fprintf(stderr, "Streaming compression round trip did not preserve the payload.\n");
        goto cleanup;
    }

    success = 1;

cleanup:
    BrotliDecoderDestroyInstance(decoder);
    BrotliEncoderDestroyInstance(encoder);
    free(decoded);
    free(compressed);
    return success;
}

static int test_decoder_error_details(void)
{
    static const uint8_t malformed_data[] = {
        0xffU, 0xffU, 0xffU, 0xffU, 0xffU, 0xffU, 0xffU, 0xffU
    };
    uint8_t output[32];
    BrotliDecoderState *decoder = BrotliDecoderCreateInstance(NULL, NULL, NULL);
    const uint8_t *next_input = malformed_data;
    uint8_t *next_output = output;
    size_t available_input = sizeof(malformed_data);
    size_t available_output = sizeof(output);
    size_t total_output = 0U;
    BrotliDecoderResult result;
    BrotliDecoderErrorCode error_code;
    const char *error_string;

    if (decoder == NULL) {
        fprintf(stderr, "Unable to create decoder for error-detail test.\n");
        return 0;
    }

    result = BrotliDecoderDecompressStream(
        decoder,
        &available_input,
        &next_input,
        &available_output,
        &next_output,
        &total_output
    );

    if (result != BROTLI_DECODER_RESULT_ERROR) {
        fprintf(stderr, "Malformed input did not produce a decoder error.\n");
        BrotliDecoderDestroyInstance(decoder);
        return 0;
    }

    error_code = BrotliDecoderGetErrorCode(decoder);
    error_string = BrotliDecoderErrorString(error_code);
    if (error_code == BROTLI_DECODER_NO_ERROR
            || error_string == NULL
            || error_string[0] == '\0') {
        fprintf(stderr, "Decoder error code or description was missing.\n");
        BrotliDecoderDestroyInstance(decoder);
        return 0;
    }

    BrotliDecoderDestroyInstance(decoder);
    return 1;
}

int main(void)
{
    uint8_t input[SMOKE_INPUT_SIZE];
    const uint32_t encoder_version = BrotliEncoderVersion();
    const uint32_t decoder_version = BrotliDecoderVersion();

    if (encoder_version != EXPECTED_BROTLI_VERSION
            || decoder_version != EXPECTED_BROTLI_VERSION) {
        fprintf(
            stderr,
            "Unexpected Brotli version: encoder=0x%08x decoder=0x%08x\n",
            (unsigned int)encoder_version,
            (unsigned int)decoder_version
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

    if (!test_decoder_error_details()) {
        return EXIT_FAILURE;
    }

    printf(
        "Brotli 1.2.0 shared-library smoke test passed "
        "(encoder=0x%08x decoder=0x%08x).\n",
        (unsigned int)encoder_version,
        (unsigned int)decoder_version
    );
    return EXIT_SUCCESS;
}
