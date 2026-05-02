#ifndef MINING_GPU_H
#define MINING_GPU_H

#include <utility> // Required for std::pair

// Declaration of the GPU mining wrapper function
std::pair<char*, char*> findHashGPU(char* header);

#endif // MINING_GPU_H