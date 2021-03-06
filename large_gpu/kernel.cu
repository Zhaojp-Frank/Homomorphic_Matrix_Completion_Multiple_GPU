#include "head.h"

__global__ void elepro(dt *t1,dt *t2,dt *tt,int k){
	
	int i = blockDim.x*blockIdx.x+threadIdx.x;
	const int temp = blockDim.x*gridDim.x;
	while(i<k){
		tt[i] = t1[i]*t2[i];
		i+=temp;
	}
	__syncthreads();

}

__global__ void elebat(dt *t1,dt *t2,dt *tt,int a,int b,int c){
// m r n
	int i = blockDim.x*blockIdx.x+threadIdx.x;
	const int temp = blockDim.x*gridDim.x;
	while(i<a*b*c){
		int tube = i/(a*b); //locate which slice
		int row = (i-tube*(a*b))/a;
		int col = (i-tube*(a*b))%a;
		tt[tube*a*b+row*a+col] = t1[row*a+col]*t2[col+tube*a];
		i+=temp;
	}
	__syncthreads();	
}

void getbatch(dt *A,dt *B,dt *sample,dt *left,dt *right,int m,int n,int r){
	// A is a random initial m*r, B is m*n, sample is m*n
	// the we need A mul each col of sample 
	// and B.*sample
	// left is r*r*n  right is r*1*n store the data we want
	dt *d_B;
	dt *d_sample;
	dt *d_Bsample;
	cudaMalloc((void**)&d_B,sizeof(dt)*m*n);
	cudaMalloc((void**)&d_sample,sizeof(dt)*m*n);
	cudaMalloc((void**)&d_Bsample,sizeof(dt)*m*n);
	cudaMemcpy(d_sample,sample,sizeof(dt)*m*n,cudaMemcpyHostToDevice);
	cudaMemcpy(d_B,B,sizeof(dt)*m*n,cudaMemcpyHostToDevice);
	dim3 th(512,1,1);
	dim3 block1((m*n+512-1)/512,1,1);
	elepro<<<block1,th>>>(d_B,d_sample,d_Bsample,m*n);
	cudaFree(d_B); // d_B is replace to d_Bsample

/*	dt *temp = new dt[m*n]();
	cudaMemcpy(temp,d_Bsample,sizeof(dt)*m*n,cudaMemcpyDeviceToHost);
	printTensor(temp,1,m*n,1);
	delete[] temp;temp=nullptr;
*/
	dt *d_Asample;
	dt *d_A;
	cudaMalloc((void**)&d_A,sizeof(dt)*m*r);
	cudaMalloc((void**)&d_Asample,sizeof(dt)*m*r*n);
	cudaMemcpy(d_A,A,sizeof(dt)*m*r,cudaMemcpyHostToDevice);
	dim3 block2((m*r*n+512-1)/512,1,1);
	elebat<<<block2,th>>>(d_A,d_sample,d_Asample,m,r,n);
	cudaFree(d_A);
	cudaFree(d_sample);

/*	dt *temp1 = new dt[m*r*n]();
	cudaMemcpy(temp1,d_Asample,sizeof(dt)*m*r*n,cudaMemcpyDeviceToHost);
	printTensor(temp1,1,m*r,n);
	delete[] temp1;temp1=nullptr;
*/
	// the we will compute batched product by cublasSgemmStridedBatched
	// A'*Ax = A'*b
	// d_Asample is m*r*n d_Bsample is m*1*n

	dt *d_left;
	cudaMalloc((void**)&d_left,sizeof(dt)*r*r*n);
	cublasHandle_t handle;
	cublasCreate(&handle);
	dt alpha = 1.0;
	dt beta = 0.0;
	cublasSgemmStridedBatched(
			handle,
			CUBLAS_OP_T,
			CUBLAS_OP_N,
			r,r,m,
			&alpha,
			d_Asample,m,m*r,
			d_Asample,m,m*r,
			&beta,
			d_left,r,r*r,
			n
			);
	
	cudaMemcpy(left,d_left,sizeof(dt)*r*r*n,cudaMemcpyDeviceToHost);
//	printTensor(left,1,r*r,n);
	
	dt *d_right;
	cudaMalloc((void**)&d_right,sizeof(dt)*r*1*n);
	cublasSgemmStridedBatched(
			handle,
			CUBLAS_OP_T,
			CUBLAS_OP_N,
			r,1,m,
			&alpha,
			d_Asample,m,m*r,
			d_Bsample,m,m,
			&beta,
			d_right,r,r,
			n
			);

	cudaMemcpy(right,d_right,sizeof(dt)*r*1*n,cudaMemcpyDeviceToHost);
//	printTensor(right,1,r*1,n);
	
	cudaFree(d_Asample);
	cudaFree(d_Bsample);
	cudaFree(d_left);
	cudaFree(d_right);

	cublasDestroy(handle);

}
void Matrixtranpose(dt *res,int a,int b){
	//solve the transpose of res origin is a b to b a
	dt *d_res = NULL;	
	dt *d_res1 = NULL;
	cudaMalloc((void**)&d_res,sizeof(dt)*a*b);	//a*c	
	cudaMalloc((void**)&d_res1,sizeof(dt)*a*b);	//b*c
	cudaMemcpy(d_res,res,sizeof(dt)*a*b,cudaMemcpyHostToDevice);
	dt alpha = 1.0;
	dt beta = 0.0;
	cublasHandle_t handle1;
	cublasCreate(&handle1);
	cublasSgeam(
		handle1,
		CUBLAS_OP_T,
		CUBLAS_OP_N,
		a,
		b,
		&alpha,
		d_res,
		b,
		&beta,
		d_res1,
		a,
		d_res1,
		a
		 );
	cudaMemcpy(res,d_res1,sizeof(dt)*a*b,cudaMemcpyDeviceToHost);
	cudaFree(d_res);
	cudaFree(d_res1);
	cublasDestroy(handle1);
}

