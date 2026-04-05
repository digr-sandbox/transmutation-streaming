from algorithm import vectorize, parallelize
from collections import List, Dict
from memory import memset_zero, memcpy, stack_allocation
from memory import UnsafePointer, alloc
from utils import StaticTuple
from sys import argv
from sys.param_env import env_get_int
from sys.terminate import exit
from sys.info import simd_width_of, size_of, num_performance_cores
import math
import os
import random
import time

comptime NUM_CONFIG_INT = 7

comptime nelts = (4 * simd_width_of[Float32]())
comptime BufferPtrFloat32 = UnsafePointer[Float32, MutExternalOrigin]

struct Matrix(Movable):
    var data: BufferPtrFloat32
    var allocated: Int
    var dims: List[Int]

    fn __init__(out self, *dims: Int):
        self.data = BufferPtrFloat32()
        self.allocated = 0
        self.dims = List[Int]()
        for i in range(len(dims)):
            self.dims.append(dims[i])
        self.alloc()

    # Constructor for creating views/slices without allocation
    fn __init__(out self, ptr: BufferPtrF
