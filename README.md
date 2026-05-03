# Milestone 2: CUDA-Accelerated Integration for High-Throughput Blockchain Networks

**Contributors:** Rayyan Hassan Salman, Ahmad Ibrahim Ahmed  

**Status:** >50% Completed (99% of processing on GPU, >75% of core non-networking code is CUDA)  
**Commits:** 20-50+ regular commits demonstrating incremental integration.

## Project Overview & Motivation
This project addresses the serialised blockchain bottleneck by transitioning the transaction validation pipeline specifically cryptographic signature verification and state-tree generation from a sequential CPU model to a massively parallel GPU environment. The primary benefit is demonstrating that hardware-accelerating the transaction validation pipeline can reduce block processing latency from seconds to milliseconds, drastically scaling network throughput without altering the core consensus protocol. This architecture mirrors the parallel execution engines of next-generation networks like Solana and Monad.

While a standard C++ blockchain framework is used to handle the foundational peer-to-peer communication, it is important to note that this networking is not considered a scalability issue for the scope of this research; it is merely required structural boilerplate. As a result, the repository contains a volume of standard C++ networking code. However, as of this milestone, more than 99% of the actual computational processing is executing on the GPU, and over 75% of our non-networking, core execution codebase consists of custom CUDA implementations.

## Hardware & Development Environment
All benchmarks, testing, and validations for this milestone were conducted on the following hardware configuration:
* **CPU:** Intel(R) Xeon(R) W-2275 CPU @ 3.30GHz (14 Cores)
* **GPU:** NVIDIA RTX A2000 12GB (3328 CUDA Cores)
* **CUDA Toolkit:** Version 11.5

## Milestone 2 Progress (The 50% Mark)
We have successfully implemented the Host-Accelerator architecture outlined in our proposal. We developed the isolated CUDA kernels and engineered the wrapper integration to safely marshal transaction batches from the host's memory space into the PCIe bus, trigger the CUDA kernels, and return the computed state back to the CPU.

### 1. SHA-256 Algorithm Acceleration
To support the core cryptographic operations, we fully ported the SHA-256 algorithm to run natively on the GPU device.
* **Implementation Detail:** We are utilizing Constant Memory for storing the SHA-256 constants (K array). This ensures zero-latency broadcast reads across all executing threads.
* **Integration:** This isolated device function (`sha256_device`) serves as the foundational hashing mechanism for both the Proof-of-Work miner and the Merkle tree generator.

### 2. Proof-of-Work (PoW) Miner
We successfully implemented a highly parallelized SHA-256 brute-force engine utilizing millions of threads to find valid cryptographic nonces for block finalization. The kernel processes multiple batches sequentially until a valid nonce is discovered.
* **Kernel Configuration:** The kernel is optimized for register usage utilizing `__launch_bounds__(256)`.
* **Performance Metric:** We achieved a consistent average speedup of **420x** compared to the sequential CPU baseline. Furthermore, peak speedups of over **800x** have been observed. This variance is due to the nature of the nonce search space; slight alterations in the input block header cause drastic shifts in the required nonce discovery time. A more detailed analytical report on this performance variance will be provided in future submissions.

### 3. Parallel Merkle Root Generator
We developed a parallel reduction kernel that takes verified transaction hashes from the mempool and recursively folds them until the Merkle Root is formed.
* **Implementation Detail:** This applies logarithmic time-complexity reduction (O(log N)) to collapse the Merkle Tree. 
* **Performance Metric:** We achieved a **21x** speedup on Merkle tree generation over the CPU baseline. 
* **Context & Current Development:** It is important to note that this 21x speedup was benchmarked on blocks containing only 1,000 transactions, whereas typical modern Bitcoin blocks contain over 4,000 transactions. To further optimize scaling for these massive transaction batches, CUDA Dynamic Parallelism (CDP) (bonus feature not taught in class) kernels are currently underway. This will engineer the GPU to autonomously spawn child grids during the recursive Merkle Tree generation, eliminating the latency of repeated CPU-to-GPU kernel launch overheads from the host framework.

## Testing & Verification
The system operates in a shadow-testing mode to guarantee cryptographic integrity.
* **Correctness:** We have verified that the GPU-generated hashes and Merkle roots match the host CPU outputs exactly.
* **Stress Testing:** The blockchain has been comprehensively tested by adding multiple blocks sequentially and verifying chain integrity. The largest transaction batch successfully tested in a single block execution was 2000 transactions/15000+ blocks.
* **Scaling:** Scalibility information will be provided once program is profiled for gpu utilisation .

## Code Structure Evidence
The repository reflects these updates through our custom CUDA library acting as the parallel execution engine. Key files include:
* `sha256_gpu.cu` / `sha256_gpu.h`: Handles the native on-chip cryptographic hashing.
* `gpu_mining.cu` / `gpu_mining.h`: Drives the massively parallel nonce discovery (420x speedup).
* `gpu_merkle.cu` / `gpu_merkle.h`: Executes the O(log N) parallel reduction for state-tree generation (21x speedup).
* `cuda_error_check.h`: Ensures safe memory marshaling and kernel execution validation across the Host-Accelerator boundary.
* `Makefile`: Contains the compilation rules linking `nvcc` and `g++`.

## Build & Run Instructions
To compile and run the accelerated blockchain node:
1. Ensure CUDA 11.5 and OpenSSL are installed on your system.
2. Compile the codebase using the provided Makefile:
   `make`
3. Execute the main program:
   `./main`
4. Follow the command-line prompts to assign a port and initialize the node (e.g., press `y` for the initial node).

## Future Prospects (Phase 2 / The Remaining 50%)
To complete the project and exceed the standard curriculum, the following phases are scheduled for the remainder of the semester:

1. **Batch ECDSA Verifier:** Developing an embarrassingly parallel kernel designed to verify thousands of digital signatures concurrently.
2. **CUDA Streams (Asynchronous Execution):** Overlapping the host framework's state management with the GPU-side cryptographic execution, ensuring neither processor sits idle while data batches move across the PCIe bus.
3. (If we find the use) **Advanced Integration:** Finalizing Foreign Function Interfaces (FFI / Bindings) to bridge the low-level CUDA drivers with high-level host frameworks.
4. **Shared Memory Optimization:** Transitioning current global memory accesses in the Merkle and Mining kernels to utilize advanced shared-memory thread synchronization for increased throughput.
5. **CUDA Dynamic Parallelism (CDP):** Engineering the GPU to autonomously spawn child execution grids during the recursive Merkle Tree generation, effectively eliminating the latency and overhead of repeated CPU-to-GPU kernel launches from the host framework.
