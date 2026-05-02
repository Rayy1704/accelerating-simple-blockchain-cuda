#include <stdio.h>
#include <string.h>
#include <stdint.h>
#include "mining_gpu.h"
// helper macros for sha-256
#define ROTR(x, n)  (((x) >> (n)) | ((x) << (32 - (n))))
#define CH(x, y, z) (((x) & (y)) ^ (~(x) & (z)))
#define MAJ(x, y, z)(((x) & (y)) ^ ((x) & (z)) ^ ((y) & (z)))
#define EP0(x)      (ROTR(x,  2) ^ ROTR(x, 13) ^ ROTR(x, 22))
#define EP1(x)      (ROTR(x,  6) ^ ROTR(x, 11) ^ ROTR(x, 25))
#define SIG0(x)     (ROTR(x,  7) ^ ROTR(x, 18) ^ ((x) >>  3))
#define SIG1(x)     (ROTR(x, 17) ^ ROTR(x, 19) ^ ((x) >> 10))

// pair<string,string> findHash(int index, string prevHash, vector<string> &merkle) {
//     string header = to_string(index) + prevHash + getMerkleRoot(merkle);
//     unsigned int nonce;
//     for (nonce = 0; nonce < 100000000000; nonce++ ) {
//         string blockHash = sha256(header + to_string(nonce));
//         if (blockHash.substr(0,6) == "000000"){
//             // cout << "nonce: " << nonce;
//             // cout << "header: " << header;
//             return make_pair(blockHash,to_string(nonce));
//             break;
//         }
//     }
//     return make_pair("fail","fail");
// }
// __global__ void findHashGPU(int index, char * prevHash, char * merkleRoot, char * resultHash, char * resultNonce) {
//     int nonce = blockIdx.x * blockDim.x + threadIdx.x;
//     if (nonce < 100000000000) {
//         string header = to_string(index) + string(prevHash) + string(merkleRoot);
//         string blockHash = sha256(header + to_string(nonce));
//         if (blockHash.substr(0,6) == "000000"){
//             // Copy the result back to the host
//             strcpy(resultHash, blockHash.c_str());
//             strcpy(resultNonce, to_string(nonce).c_str());
//         }
//     }
// }

__constant__ uint32_t K[64] = {
    0x428a2f98, 0x71374491, 0xb5c0fbcf, 0xe9b5dba5,
    0x3956c25b, 0x59f111f1, 0x923f82a4, 0xab1c5ed5,
    0xd807aa98, 0x12835b01, 0x243185be, 0x550c7dc3,
    0x72be5d74, 0x80deb1fe, 0x9bdc06a7, 0xc19bf174,
    0xe49b69c1, 0xefbe4786, 0x0fc19dc6, 0x240ca1cc,
    0x2de92c6f, 0x4a7484aa, 0x5cb0a9dc, 0x76f988da,
    0x983e5152, 0xa831c66d, 0xb00327c8, 0xbf597fc7,
    0xc6e00bf3, 0xd5a79147, 0x06ca6351, 0x14292967,
    0x27b70a85, 0x2e1b2138, 0x4d2c6dfc, 0x53380d13,
    0x650a7354, 0x766a0abb, 0x81c2c92e, 0x92722c85,
    0xa2bfe8a1, 0xa81a664b, 0xc24b8b70, 0xc76c51a3,
    0xd192e819, 0xd6990624, 0xf40e3585, 0x106aa070,
    0x19a4c116, 0x1e376c08, 0x2748774c, 0x34b0bcb5,
    0x391c0cb3, 0x4ed8aa4a, 0x5b9cca4f, 0x682e6ff3,
    0x748f82ee, 0x78a5636f, 0x84c87814, 0x8cc70208,
    0x90befffa, 0xa4506ceb, 0xbef9a3f7, 0xc67178f2
};

__device__ void sha256_device(const unsigned char* input, int len, unsigned char* output){
    //initia; hash values
    uint32_t h0 = 0x6a09e667, h1 = 0xbb67ae85,
             h2 = 0x3c6ef372, h3 = 0xa54ff53a,
             h4 = 0x510e527f, h5 = 0x9b05688c,
             h6 = 0x1f83d9ab, h7 = 0x5be0cd19;
    unsigned char msg[128];   // enough for header+nonce + padding
    memset(msg, 0, 128); //fill buffer with zeros
    memcpy(msg, input, len); // copy header+nonce into buffer

    msg[len] = 0x80; //append 1 to buffer after message

    uint64_t bitlen = (uint64_t)len * 8; // length of message in bits
    int padded_len = ((len + 9 + 63) / 64) * 64;  // total length after padding 
    // append original message length in bits at the end of the buffer
    msg[padded_len - 1] = (unsigned char)(bitlen);
    msg[padded_len - 2] = (unsigned char)(bitlen >> 8);
    msg[padded_len - 3] = (unsigned char)(bitlen >> 16);
    msg[padded_len - 4] = (unsigned char)(bitlen >> 24);
    msg[padded_len - 5] = (unsigned char)(bitlen >> 32);
    msg[padded_len - 6] = (unsigned char)(bitlen >> 40);
    msg[padded_len - 7] = (unsigned char)(bitlen >> 48);
    msg[padded_len - 8] = (unsigned char)(bitlen >> 56);

    //processing each 64 byte chunk together 

    // Process each 64-byte chunk
    for (int chunk = 0; chunk < padded_len; chunk += 64) {
        uint32_t W[64];

        // take first 16 words from chunk
        for (int i = 0; i < 16; i++) {
            W[i] = ((uint32_t)msg[chunk + i*4    ] << 24) |
                   ((uint32_t)msg[chunk + i*4 + 1] << 16) |
                   ((uint32_t)msg[chunk + i*4 + 2] <<  8) |
                   ((uint32_t)msg[chunk + i*4 + 3]);
        }

        // remaining 48 words: derived from previous words
        for (int i = 16; i < 64; i++) {
            W[i] = SIG1(W[i-2]) + W[i-7] + SIG0(W[i-15]) + W[i-16];
        }

        // sha256 logic: 64 rounds of mixing
        uint32_t a = h0, b = h1, c = h2, d = h3,
                 e = h4, f = h5, g = h6, h = h7;

        for (int i = 0; i < 64; i++) {
            uint32_t T1 = h + EP1(e) + CH(e,f,g) + K[i] + W[i];
            uint32_t T2 = EP0(a) + MAJ(a,b,c);
            h = g; g = f; f = e; e = d + T1;
            d = c; c = b; b = a; a = T1 + T2;
        }

        // add compressed chunk to current hash value
        h0 += a; h1 += b; h2 += c; h3 += d;
        h4 += e; h5 += f; h6 += g; h7 += h;
    }
    // produce final hash value (big-endian)
    // ── Process each 64-byte chunk
    for (int chunk = 0; chunk < padded_len; chunk += 64) {

        // build message schedule W[0..63]
        uint32_t W[64];

        // first 16 words: straight from the message chunk
        for (int i = 0; i < 16; i++) {
            W[i] = ((uint32_t)msg[chunk + i*4    ] << 24) |
                   ((uint32_t)msg[chunk + i*4 + 1] << 16) |
                   ((uint32_t)msg[chunk + i*4 + 2] <<  8) |
                   ((uint32_t)msg[chunk + i*4 + 3]);
        }

        // remaining 48 words: derived from previous words
        for (int i = 16; i < 64; i++) {
            W[i] = SIG1(W[i-2]) + W[i-7] + SIG0(W[i-15]) + W[i-16];
        }

        // ── Compression — the core of SHA-256
        uint32_t a = h0, b = h1, c = h2, d = h3,
                 e = h4, f = h5, g = h6, h = h7;

        for (int i = 0; i < 64; i++) {
            uint32_t T1 = h + EP1(e) + CH(e,f,g) + K[i] + W[i];
            uint32_t T2 = EP0(a) + MAJ(a,b,c);
            h = g; g = f; f = e; e = d + T1;
            d = c; c = b; b = a; a = T1 + T2;
        }

        // ── Add compressed chunk to current hash
        h0 += a; h1 += b; h2 += c; h3 += d;
        h4 += e; h5 += f; h6 += g; h7 += h;
    }
    // ── Produce final 32-byte hash (big-endian)
    output[ 0] = (h0 >> 24) & 0xFF; output[ 1] = (h0 >> 16) & 0xFF;
    output[ 2] = (h0 >>  8) & 0xFF; output[ 3] = (h0)       & 0xFF;
    output[ 4] = (h1 >> 24) & 0xFF; output[ 5] = (h1 >> 16) & 0xFF;
    output[ 6] = (h1 >>  8) & 0xFF; output[ 7] = (h1)       & 0xFF;
    output[ 8] = (h2 >> 24) & 0xFF; output[ 9] = (h2 >> 16) & 0xFF;
    output[10] = (h2 >>  8) & 0xFF; output[11] = (h2)       & 0xFF;
    output[12] = (h3 >> 24) & 0xFF; output[13] = (h3 >> 16) & 0xFF;
    output[14] = (h3 >>  8) & 0xFF; output[15] = (h3)       & 0xFF;
    output[16] = (h4 >> 24) & 0xFF; output[17] = (h4 >> 16) & 0xFF;
    output[18] = (h4 >>  8) & 0xFF; output[19] = (h4)       & 0xFF;
    output[20] = (h5 >> 24) & 0xFF; output[21] = (h5 >> 16) & 0xFF;
    output[22] = (h5 >>  8) & 0xFF; output[23] = (h5)       & 0xFF;
    output[24] = (h6 >> 24) & 0xFF; output[25] = (h6 >> 16) & 0xFF;
    output[26] = (h6 >>  8) & 0xFF; output[27] = (h6)       & 0xFF;
    output[28] = (h7 >> 24) & 0xFF; output[29] = (h7 >> 16) & 0xFF;
    output[30] = (h7 >>  8) & 0xFF; output[31] = (h7)       & 0xFF;
}

__device__ bool hasLeadingZeros(unsigned char* hash) {
    int fullBytes = 6;
    for (int i = 0; i < fullBytes; i++) {
        if (hash[i] != 0x00) return false;
    }
    return true;
}

__global__ 

void mineKernel(const unsigned char* header,int headerLen,unsigned int batchStart,int difficulty,unsigned int* resultNonce,int* found){
    if (*found) return // already found hash, skip work
    unsigned int nonce = batchStart + blockIdx.x * blockDim.x + threadIdx.x; // calculate nonce
    unsigned char input[128]; // buffer for header + nonce and padding
    memcpy(input, header, headerLen); // copy header into buffer]
}