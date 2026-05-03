#include "gpu_merkle.h"
#include <cuda_error_check.h>
#include "sha256_gpu.h"
__global__ 
void merkelKernel(char *header, int headerLen){
    int i = blockIdx.x * blockDim.x + threadIdx.x;
    // each thread handles a consecutive pair of hashes
    if(i*2+1>=headerLen) return; // out of bounds
    //for hash indexing

    unsigned char* left = (unsigned char*) (header + (i * 2)*32);// left hash
    unsigned char* right = (unsigned char*) (header + (i * 2+1)*32); // right hash
    unsigned char * out = (unsigned char * )(header+i);// output slot (thread itself)
    //for calculating
    unsigned char combined_hashes[64];
    memcpy(combined_hashes, left, 32);
    memcpy(combined_hashes + 32, right, 32);

    //calling self created hashfunction to hash them together
    unsigned char hash_output[32]; // output of the hash function
    sha256_device(combined_hashes, 64, hash_output); // hash the combined hashes
    memcpy(out, hash_output, 32); // store resultant hash into thread id place
}

std :: string getMerkleRootGPU(std::vector <std::string>& merkle){ // function definition as per tko 22 standards
    std :: vector<std :: string> hashes = merkle; // start with the initial level of hashes
    if(hashes.size()%2!=0){ // incase of odd number of hashes
        hashes.push_back(hashes.back()); // duplicate the last hash
    }
    int numHashes=hashes.size();
    unsigned char h_hashes =. new unsigned char [numHashes*32];
    for (int i=0;i<numHashes;i++){
        memcpy(h_hashes+i*32, hashes[i].c_str(), 32); // copy the hashes into a continous memory
    }
    unsigned char *d_hashes;
    CUDA_CHECK(cudaMalloc(&d_hashes, numHashes*32)); // allocate memory on the GPU
    CUDA_CHECK(cudaMemcpy(d_hashes, h_hashes, numHashes*32, cudaMemcpyHostToDevice)); // copy the hashes to the GPU
    int count = numHashes;
    while(count>1){ // while there are more than 1 hash
        if(count%2!=0){ // for odd number of hashes
            CUDA_CHECK(cudaMemcpy(d_hashes+count*32, d_hashes+(count-1)*32, 32, cudaMemcpyDeviceToDevice)); // duplicate the last hash on the GPU
            count++; // update the count
        }
        int pairs = count/2;
        int threads = 256; // number of threads per block
        int blocks = (pairs+threads-1)/threads; // number of blocks needed
        dim3 blocks(blocks);
        dim3 threads(threads);
        merkelKernel<<<blocks, threads>>>(d_hashes, count); // launch the kernel to compute the next level of hashes
        CUDA_CHECK(cudaDeviceSynchronize()); // wait for the kernel to finish
        count = (count+1)/2; // update the count for the next level
    }

    unsigned char h_merkle_root[32];
    cuda memcpy(h_merkle_root, d_hashes, 32, cudaMemcpyDeviceToHost); // copy the final merkle root back to the host

    char rootHex[65];
    for (int i=0;i<32;i++){
        sprintf(rootHex+i*2, "%02x", h_merkle_root[i]); // convert the merkle root to hexadecimal string
    }
    rootHex[64]='\0'; // null terminate the string
    cudaFree(d_hashes); // free the GPU memory
    delete[] h_hashes; // free the host memory
    return std::string(rootHex); // return the merkle root as a string
}