void swap(int arr[], int i, int j) {
	int temp = arr[i];
	arr[i] = arr[j];
	arr[j] = temp;
}
// low-high in increasing order
void quickSort3Ways(int arr[], int lowIndex, int highIndex) {
	if(lowIndex >= highIndex) return;
	int i = lowIndex + 1;
	int pivot_value = arr[lowIndex];
	int lt = lowIndex;
	int gt = highIndex;
	while(i <= gt) {
		if(arr[i] < pivot_value) {
			swap(arr, i++, lt++);
		}
		else if(arr[i] > pivot_value) {
			swap(arr, i, gt--);
		}
		else {
			i ++;
		}
	}
	quickSort3Ways(arr, lowIndex, lt - 1);
	quickSort3Ways(arr, gt + 1, highIndex);
}
//#include <stdio.h> 
#include "trap.h"
int main() {
	int arr[100];
	int j;
	for(j = 0; j < 100; j += 2) {
		arr[j] = 0;  
		arr[j + 1] = 1; 
	}
	quickSort3Ways(arr, 0, 99);

	for(j = 0; j < 50; j ++) {
		ASSERT(arr[j] == 0);
		/*if(arr[j] != 0) {
			printf("arr[%d] != 0", j);
		}*/
	}
	for(;j < 100; j ++) {
		ASSERT(arr[j] == 1);
		/*if(arr[j] != 1) {
			printf("arr[%d] != 1", j);
		}*/
	}
	
	return 0;
}
			

	
			 
