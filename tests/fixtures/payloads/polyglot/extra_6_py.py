# Copyright 2015 The TensorFlow Authors. All Rights Reserved.
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
# ==============================================================================
"""Classes and functions used to construct graphs."""
# pylint: disable=g-bad-name
import collections
from collections.abc import Callable, Iterator, Sequence
import contextlib
import copy
import enum
import re
import sys
import threading
import types
from typing import cast, TypeVar, Any, AnyStr, NoReturn, Optional, Pattern, Union, ContextManager

from absl import app
import numpy as np
from numpy import typing as npt

from google.protobuf import message
from tensorflow.core.framework import attr_value_pb2
from tensorflow.core.framework import full_type_pb2
from tensorflow.core.framework import function_pb2
from tensorflow.core.framework import graph_pb2
from tensorflow.core.framework import node_def_pb2
from tensorflow.core.framework import op_def_pb2
from tensorflow.core.framework import types_pb2
from tensorflow.core.framework import versions_pb2
from tensorflow.core.protobuf import config_pb2
# pywrap_tensorflow must be imported first to avoid protobuf issues.
# (b/143110113)
# pylint: disable=invalid-import-order,g-bad-import-order,unused-import
from tensorflow.python import pywrap_tensorflow
from tensorflow.python import pywrap_tfe
# pylint: enable=invalid-import-order,g-bad-import-order,unused-import
from tensorflow.python import tf2
from tensorflow.python.client import pywrap_tf_session
from tensorflow.python.eager import context
from tensorflow.python.eager import core
from tensorflow.python.eager import monitoring
from tensorflow.python.eager import record
from tensorflow.python.framework import c_api_util
from tensorflow.python.framework import composite_tensor
from tensorflow.python.framework import device as pydev
from tensorflow.python.framework import dtypes
from tensorflow.python.framework import errors
from tensorflow.python.framework import op_callbacks
from tensorflow.python.framework import registry
from tensorflow.python.framework import stack
from tensorflow.python.framework import tensor as tensor_lib
from tensorflow.python.framework import tensor_conversion_registry
from tensorflow.python.framework import tensor_shape
from tensorflow.python.framework import tensor_util
from tensorflow.python.framework import traceable_stack
from tensorflow.python.framework import versions
from tensorflow.python.ops import control_flow_util
from tensorflow.python.ops import handle_data_util
from tensorflow.python.platform import tf_logging as logging
from tensorflow.python.profiler import trace as profiler_trace
from tensorflow.python.types import core as core_tf_types
from tensorflow.python.types import internal
from tensorflow.python.util import compat
from tensorflow.python.util import decorator_utils
from tensorflow.python.util import deprecation
from tensorflow.python.util import function_utils
from tensorflow.python.util import lock_util
from tensorflow.python.util import object_identity
from tensorflow.python.util import tf_contextlib
from tensorflow.python.util import tf_stack
from tensorflow.python.util import traceback_utils
from tensorflow.python.util.compat import collections_abc
from tensorflow.python.util.deprecation import deprecated_args
from tensorflow.python.util.tf_export import kwarg_only
from tensorflow.python.util.tf_export import tf_export

_T = TypeVar("_T")
GraphType = TypeVar("GraphType", bound="Graph")
OpStatsType = TypeVar("OpStatsType", bound="OpStats")
OperationType = TypeVar("OperationType", bound="Operation")
EagerTensorType = TypeVar("EagerTensorType", bound="_EagerTensorBase")


# TODO(b/307794935): Remove after bug is fixed.
is_oss = True  # Updated by copybara

# Temporary global switches determining if we should enable the work-in-progress
# calls to the C API. These will be removed once all functionality is supported.
_USE_C_API: bool = True
_USE_C_SHAPES: bool = True


_api_usage_gauge = monitoring.BoolGauge(
    "/tensorflow/api/ops_eager_execution",
    "Whether ops.enable_eager_execution() is called.")

_control_flow_api_gauge = monitoring.BoolGauge(
    "/tensorflow/api/enable_control_flow_v2",
    "Whether enable_control_flow_v2() is called.")

_tf_function_api_gauge = monitoring.BoolGauge(
    "/tensorflow/api/tf_function",
    "Whether tf.function() is used.")

# pylint: disable=protected-access
_DTYPES_INTERN_TABLE: dict[types_pb2.DataType, dtypes.DType] = (
    dtypes._INTERN_TABLE)
# pylint: enable=protected-access


def tensor_id(tensor) -> Any:
  """Returns a unique identifier for this Tensor."""
  return tensor._id  # pylint: disable=protected-access


class _UserDeviceSpec(object):
  """Store user-specified device and provide computation of merged device."""

  def __init__(self, device_name_or_function) -> None:
    self._device_name_or_function = device_name_or_function
    self.display_name = str(self._device_name_or_function)
    self.function = device_name_or_function
    self.raw_string = None

    if isinstance(device_name_or_function, pydev.MergeDevice):
      self.is_null_merge = device_name_or_function.is_null_merge

    elif callable(device_name_or_function):
      self.is_null_merge = False
      dev_func = self._device_name_or_function
      func_name = function_utils.get_func_name(dev_func)
      func_code = function_utils.get_func_code(dev_func)
      if func_code:
        fname = func_code.co_filename
        lineno = func_code.co_firstlineno
      else:
        fname = "unknown"
        lineno = -1
      self.display_name = "%s<%s, %d>" % (func_name, fname, lineno)

    elif device_name_or_function is None:
      # NOTE(taylorrobie): This MUST be False. None signals a break in the
      #   device stack, so `is_null_merge` must be False for such a case to
      #   allow callers to safely skip over null merges without missing a None.
      self.is_null_merge = False

    else:
      self.raw_string = device_name_or_function
      self.function = pydev.merge_device(device_name_or_function)
      self.is_null_merge = self.function.is_null_merge

    # We perform this check in __init__ because it is of non-trivial cost,
    # and self.string_merge is typically called many times.
    self.fast_string_merge = isinstance(self.function, pydev.MergeDevice)

  def string_merge(self, node_def) -> str:
    if self.fast_string_merge:
      return self.function.shortcut_string_merge(node_def)

    return compat.as_str(_device_string(self.function(node_def)))


class NullContextmanager(contextlib.AbstractContextManager[None]):

  def __init__(self, *args, **kwargs) -> None:
    pass

  def __enter__(self) -> None:
    pass

  def __exit__(self, type_arg, value_arg, traceback_arg) -> bool:
    return False  # False values do not suppress exceptions


def _as_graph_element(obj):
  """Convert `obj` to a graph element if possible, otherwise return `None`.

  Args:
    obj: Object to convert.

  Returns:
    The result of `obj._as_graph_element()` if that method is available;
        otherwise `None`.
  """
  conv_fn = getattr(obj, "_as_graph_element", None)
  if conv_fn and callable(conv_fn):
    return conv_fn()
  return None


# Deprecated - legacy purposes only.
def is_dense_tensor_like(t) -> bool:
  return isinstance(t, core_tf_types.Tensor)


def uid() -> int:
  """A unique (within this program execution) integer."""
  return pywrap_tfe.TFE_Py_UID()


def numpy_text(tensor, is_repr=False) -> str:
  """Human readable representation of a tensor's numpy value."""
  if tensor.dtype.is_numpy_compatible:
    # pylint: disable=protected-access
    tensor_numpy = tensor._numpy()
    if is_repr:
      if np.isscalar(tensor_numpy) and not isinstance(tensor_numpy, bytes):
        # .item() converts the numpy scalars to python items.
        text = repr(tensor_numpy.item())
      else:
        text = repr(tensor_numpy)
    else:
      text = str(tensor_numpy)
    # pylint: enable=protected-access
  else:
    text = "<unprintable>"
  if "\n" in text:
    text = "\n" + text
  return text


def value_text(tensor, is_repr=False) -> AnyStr:
  """Either the NumPy value or a custom TensorFlow formatting of `tensor`.

  Custom formatting is used for custom device tensors, e.g. parallel tensors
  with multiple components on different devices.

  Args:
    tensor: The tensor to format.
    is_repr: Controls the style/verbosity of formatting.

  Returns:
    The formatted tensor.
  """
  # pylint: disable=protected-access  # friend access
  if tensor._prefer_custom_summarizer():
    text = tensor._summarize_value()
    # pylint: enable=protected-access
    if is_repr:
      text = "value=" + text
  else:
    text = numpy_text(tensor, is_repr=is_repr)
    if is_repr:
      text = "numpy=" + text
  return text


@tf_export("__internal__.SymbolicTensor")
class SymbolicTensor(pywrap_tf_session.PyTensor, tensor_lib.Tensor):
  """A symbolic tensor from a graph or tf.function."""

  def __new__(cls, op, value_index, dtype, unique_id=None) -> "SymbolicTensor":
    if unique_id is None:
      unique_id = uid()
    return pywrap_tf_session.PyTensor.__new__(
        SymbolicTensor, op, value_index, dtypes.as_dtype(dtype), unique_id
    )

  def __copy__(self) -> "SymbolicTensor":
    cls = self.__class__
    result = cls.__new__(cls, self.op, self.value_index, self.dtype, self._id)
    result.__dict__.update(self.__dict__)
    return result


def _create_graph_constant(
    value, dtype, shape, name, verify_shape, allow_broadcast
) -> tensor_lib.Tensor:
  """Create a graph constant and invoke constant callbacks."""
  g = get_default_graph()
  tensor_value = attr_value_pb2.AttrValue()
  tensor_value.tensor.CopyFrom(
      tensor_util.make_tensor_proto(
          value, dtype=dtype, shape=shape, verify_shape=verify_shape,
          allow_broadcast=allow_broadcast))
  dtype_value = attr_value_pb2.AttrValue(type=tensor_value.tensor.dtype)
  attrs = {"value": tensor_value, "dtype": dtype_value}
  const_tensor = g._create_op_internal(  # pylint: disable=protected-access
      "Const", [], [dtype_value.type], attrs=attrs, name=name).outputs[0]

  if op_callbacks.should_invoke_op_callbacks():
    # TODO(b/147670703): Once the special-op creation code paths
    # are unified. Remove this `if` block.
    callback_outputs = op_callbacks.invoke_op_callbacks(
        "Const", tuple(), attrs, (const_tensor,), op_name=name, graph=g)
    if callback_outputs is not None:
      [const_tensor] = callback_outputs
  return const_tensor


class _EagerTensorBase(
    tensor_lib.Tensor, internal.NativeObject, core_tf_types.Value):
  """Base class for EagerTensor."""

  # __complex__, __int__, __float__ and __index__ may copy the tensor to CPU and
  # only work for scalars; values are cast as per numpy.
  def __complex__(self) -> complex:
    return complex(self._numpy())

  def __int__(self) -> int:
    return int(self._numpy())

  def __float__(self) -> float:
    return float(self._numpy())

  def __index__(self) -> int:
    return cast(np.ndarray, self._numpy()).__index__()

  def __bool__(self) -> bool:
    x = self._numpy()
    if isinstance(x, np.ndarray):
      return bool(x.size > 0 and x)
    else:
      return bool(x)

  __nonzero__ = __bool__

  def __format__(self, format_spec) -> str:
    if self._prefer_custom_summarizer():
      return self._summarize_value().__format__(format_spec)
    elif self.dtype.is_numpy_compatible:
      # Not numpy_text here, otherwise the __format__ behaves differently.
      return self._numpy().__format__(format_spec)
    else:
      return "<unprintable>".__format__(format_spec)  # pytype: disable=attribute-error

  def __reduce__(self):
    return convert_to_tensor, (self._numpy(),)

  def __copy__(self: EagerTensorType) -> EagerTensorType:
    # Eager Tensors are immutable so it's safe to return themselves as a copy.
    return self

  def __deepcopy__(self: EagerTensorType, memo) -> EagerTensorType:
    # Eager Tensors are immutable so it's safe to return themselves as a copy.
    del memo
    return self

  def __str__(self) -> str:
    return "tf.Tensor(%s, shape=%s, dtype=%s)" % (
        value_text(self, is_repr=False), self.shape, self.dtype.name)

  def __repr__(self) -> str:
    return "<tf.Tensor: shape=%s, dtype=%s, %s>" % (
        self.shape, self.dtype.name, value_text(self, is_repr=True))

  def __len__(self) -> int:
    """Returns the length of the first dimension in the Tensor."""
    if not self.shape.ndims:
      raise TypeError("Scalar tensor has no `len()`")
    # pylint: disable=protected-access
    try:
      return self._shape_tuple()[0]
    except core._NotOkStatusException as e:
      raise core._status_to_exception(e) from None

  def __array__(self, dtype=None) -> np.ndarray:
    a = self._numpy()
    if not dtype:
      return cast(np.ndarray, a)

    return np.array(a, dtype=dtype)

  def __dlpack__(
      self, *, stream=None, max_version=None, dl_device=None, copy=None  # pylint: disable=redefined-outer-name
  ):
    del max_version  # Unused
    if stream is not None:
      raise RuntimeError(
          "tf.Tensor does not support DLPack export with a non-None stream"
      )
    if dl_device is not None:
      raise RuntimeError(
          "tf.Tensor does not support DLPack export with a non-None dl_device"
      )
    if copy:
      raise RuntimeError(
          "tf.Tensor does not support DLPack export with a copy=True"
      )
    return pywrap_tfe.TFE_ToDlpackCapsule(self)

  def __dlpack_device__(self):
    return pywrap_tfe.TFE_DlpackDevice(self)

  def __hash__(self) -> int:
    # EagerTensors are never hashable.
    raise TypeError("Tensor is unhashable. "
                    "Instead, use tensor.ref() as the key.")

  def _numpy_internal(self) -> npt.ArrayLike:
    raise NotImplementedError()

  def _numpy(self) -> npt.ArrayLike:
    try:
      return self._numpy_internal()
    except core._NotOkStatusException as e:  # pylint: disable=protected-access
      raise core._status_to_exception(e) from None  # pylint: disable=protected-access

  @property
  def dtype(self) -> dtypes.DType:
    # Note: using the intern table directly here as this is
    # performance-sensitive in some models.
    return dtypes._INTERN_TABLE[self._datatype_enum()]  # pylint: disable=protected-access

  def numpy(self) -> npt.ArrayLike:
    """Copy of the contents of this Tensor into a NumPy array or scalar.

    Unlike NumPy arrays, Tensors are immutable, so this method has to copy
    the contents to ensure safety. Use `memoryview` to get a readonly
    view of the contents without doing a copy:

    >>> t = tf.constant([42])
    >>> np.asarray(memoryview(t))
    array([42], dtype=int32)

    Note that `memoryview` is only zero-copy for Tensors on CPU. If a Tensor
    is on GPU, it will have to be transferred to CPU first in order for
    `memoryview` to work.

    Returns:
      A NumPy array of the same shape and dtype or a NumPy scalar, if this
      Tensor has rank 0.

    Raises:
      ValueError: If the dtype of this Tensor does not have a compatible
        NumPy dtype.
    """
    # TODO(slebedev): Consider avoiding a copy for non-CPU or remote tensors.
    maybe_arr = self._numpy()  # pylint: disable=protected-access
    return maybe_arr.copy() if isinstance(maybe_arr, np.ndarray) else maybe_arr

  @property
  def backing_device(self):
    """Returns the name of the device holding this tensor's memory.

    `.backing_device` is usually the same as `.device`, which returns
    the device on which the kernel of the operation that produced this tensor
    ran. However, some operations can produce tensors on a different device
    (e.g., an operation that executes on the GPU but produces output tensors
    in host memory).
    """
    raise NotImplementedError()

  def _datatype_enum(self) -> NoReturn:
    raise NotImplementedError()

  def _shape_tuple(self) -> NoReturn:
    """The shape of this Tensor, as a tuple.

    This is more performant than tuple(shape().as_list()) as it avoids
    two list and one object creation. Marked private for now as from an API
    perspective, it would be better to have a single performant way of
    getting a shape rather than exposing shape() and shape_tuple()
    (and heaven forbid, shape_list() etc. as well!). Punting on that for now,
    but ideally one would work things out and remove the need for this method.

    Returns:
      tuple with the shape.
    """
    raise NotImplementedError()

  def _rank(self) -> NoReturn:
    """Integer rank of this Tensor.

    Unlike regular Tensors, the rank is always known for EagerTensors.

    This is more performant than len(self._shape_tuple())

    Returns:
      Integer rank
    """
    raise NotImplementedError()

  def _num_elements(self) -> NoReturn:
    """Number of elements of this Tensor.

    Unlike regular Tensors, the number of elements is always known for
    EagerTensors.

    This is more performant than tensor.shape.num_elements

    Returns:
      Long - num elements in the tensor
    """
    raise NotImplementedError()

  def _copy_to_device(self, device_name) -> NoReturn:  # pylint: disable=redefined-outer-name
    raise NotImplementedError()

  @staticmethod
  def _override_operator(name, func) -> None:
    setattr(_EagerTensorBase, name, func)

  def _copy_nograd(
      self: EagerTensorType, ctx=None, device_name=None,
  ) -> EagerTensorType:
    """Copies tensor to dest device, but doesn't record the operation."""
    # Creates a new tensor on the dest device.
    if ctx is None:
      ctx = context.context()
    if device_name is None:
      device_name = ctx.device_name
    # pylint: disable=protected-access
    try:
      ctx.ensure_initialized()
      new_tensor = self._copy_to_device(device_name)
    except core._NotOkStatusException as e:
      raise core._status_to_exception(e) from None
    return new_tensor

  def _copy(
      self: EagerTensorType, ctx=None, device_name=None,
  ) -> EagerTensorType:
    """Copies tensor to dest device."""
    new_tensor = self._copy_nograd(ctx, device_name)
    # Record the copy on tape and define backprop copy as well.
    if context.executing_eagerly():
      self_device = self.device

      def grad_fun(dresult):
        return [
            dresult._copy(device_name=self_device)
            if hasattr(dresult, "_copy") else dresult
        ]

      record.record_operation("_copy", [new_tensor], [self], grad_fun)
    return new_tensor
    # pylint: enable=protected-access

  @property
  def shape(self) -> tensor_shape.TensorShape:
    if self._tensor_shape is None:  # pylint: disable=access-member-before-definition
      # pylint: disable=protected-access
      try:
        # `_tensor_shape` is declared and defined in the definition of
        # `EagerTensor`, in C.
        self._tensor_shape = tensor_shape.TensorShape(self._shape_tuple())
      except core._NotOkStatusException as e:
        raise core._status_to_exception(e) from None

    return self._tensor_shape

  def get_shape(self) -> tensor_shape.TensorShape:
    """Alias of Tensor.shape."""
    return self.shape

  def _shape_as_list(self) -> list[int]:
    """The shape of the tensor as a list."""
    return list(self._shape_tuple())

  @deprecation.deprecated(
      None, "Use tf.identity with explicit device placement instead.")
  def cpu(self: EagerTensorType) -> EagerTensorType:
    """A copy of this Tensor with contents backed by host memory."""
    return self._copy(context.context(), "CPU:0")

  @deprecation.deprecated(None, "Use tf.identity instead.")
  def gpu(self: EagerTensorType, gpu_index=0) -> EagerTensorType:
    """A copy of this Tensor with contents backed by memory on the GPU.

    Args:
      gpu_index: Identifies which GPU to place the contents on the returned
        Tensor in.

    Returns:
      A GPU-memory backed Tensor object initialized with the same contents
      as this Tensor.
    """
    return self._copy(context.context(), "GPU:" + str(gpu_index))

  def set_shape(self, shape) -> None:
    # pylint: disable=protected-access
    shape = tensor_shape.as_shape(shape)
    shape_dims = shape._dims
    if shape_dims is None:
      return
    self_dims = self.shape._dims
    if len(shape_dims) != len(self_dims):
      raise ValueError(f"Tensor's shape {self.shape} is not compatible "
                       f"with supplied shape {shape}.")
    for shape_dim, self_dim in zip(shape_dims, self_dims):
      if shape_dim is not None and self_dim != shape_dim:
        raise ValueError(f"Tensor's shape {self.shape} is not compatible "
                         f"with supplied shape {shape}.")
    # pylint: enable=protected-access

  # Methods not supported / implemented for Eager Tensors.
  @property
  def op(self) -> NoReturn:
    raise AttributeError(
        "Tensor.op is undefined when eager execution is enabled.")

  @property
  def graph(self) -> NoReturn:
    raise AttributeError(
        "Tensor.graph is undefined when eager execution is enabled.")

  @property
  def name(self) -> NoReturn:
    raise AttributeError(
        "Tensor.name is undefined when eager execution is enabled.")

  @property
  def value_index(self) -> NoReturn:
    raise AttributeError(
        "Tensor.value_index is undefined when eager execution is enabled.")

  def consumers(self) -> NoReturn:
    raise NotImplementedError(
        "Tensor.consumers is undefined when eager execution is enabled.")

  def _add_consumer(self, consumer) -> NoReturn:
    raise NotImplementedError(
        "_add_consumer not supported when eager execution is enabled.")

  def _as_node_def_input(self) -> NoReturn:
    raise NotImplementedError(
        "_as_node_def_input not supported when eager execution is enabled.")

  def _as_tf_output(self) -> NoReturn:
    raise NotImplementedError(
        "_as_tf_output not supported when eager execution is enabled.")

  def eval(self, feed_dict=None, session=None) -> NoReturn:
    raise NotImplementedError(
        "eval is not supported when eager execution is enabled, "
        "is .numpy() what you're looking for?")

  def __tf_tensor__(
      self, dtype: Optional[dtypes.DType] = None, name: Optional[str] = None
      ) -> tensor_lib.Tensor:
    if not context.executing_eagerly():
      graph = get_default_graph()
      if not graph.building_function:
        raise RuntimeError(
            _add_error_prefix(
                "Attempting to capture an EagerTensor without "
                "building a function.",
                name=name))
      return graph.capture(self, name=name)
    return super().__tf_tensor__(dtype, name)

  def _capture_as_const(self, name) -> Optional[tensor_lib.Tensor]:
    """Capture the EagerTensor to a graph constant tensor."""
    with control_dependencies(None):
      constant_value = tensor_util.constant_value(self)
      if constant_value is None:
        # Some eager tensors, e.g. parallel tensors, are not convertible to
        # a single constant. Return None in this case and the caller graph
        # would create a placeholder instead.
        return None

      const_tensor = _create_graph_constant(
          constant_value, dtype=self.dtype, shape=self.shape, name=name,
          verify_shape=False, allow_broadcast=True)
    return const_tensor


# This call creates an EagerTensor class, as a subclass of _EagerTensorBase, and
# registers it with the current module.
# It is exposed as an __internal__ api for now (b/171081052), though we
# expect it to be eventually covered by tf Tensor types and typing.
EagerTensor = tf_export("__internal__.EagerTensor", v1=[])(
    pywrap_tfe.TFE_Py_InitEagerTensor(_EagerTensorBase))


def _add_error_prefix(msg: str, *, name: Optional[str] = None) -> str:
  return msg if name is None else f"{name}: {msg}"


def pack_eager_tensors(tensors, ctx=None) -> EagerTensor:
  """Pack multiple `EagerTensor`s of the same dtype and shape.

  Args:
    tensors: a list of EagerTensors to pack.
    ctx: context.context().

  Returns:
    A packed EagerTensor.
  """
  if not isinstance(tensors, list):
    raise TypeError(f"tensors must be a list, but got a {type(tensors)}")

  if not tensors:
    raise ValueError("Cannot pack an empty list of tensors.")

  dtype = tensors[0].dtype
  shape = tensors[0].shape
  handle_data = tensors[0]._handle_data  # pylint: disable=protected-access
  is_resource = dtype == dtypes.resource
  for i in range(len(tensors)):
    t = tensors[i]
    if not isinstance(t, EagerTensor):
      raise TypeError(f"All tensors being packed must be EagerTensor. "
                      f"Found an item of type {type(t)}.")

    if t.dtype != dtype:
      raise ValueError(
          f"All tensors being packed should have the same dtype {dtype}, "
          f"but the {i}-th tensor is of dtype {t.dtype}")
    if t.shape != shape:
      raise ValueError(
          f"All tensors being packed should have the same shape {shape}, "
          f"but the {i}-th tensor is of shape {t.shape}")
    # pylint: disable=protected-access
    if is_resource and t._handle_data != handle_data:
      raise ValueError(
          f"All tensors being packed should have the same handle data "
          f"{handle_data}, "
          f"but the {i}-th tensor is of handle data {t._handle_data}")
    # pylint: enable=protected-access

  if ctx is None:
    ctx = context.context()

  # Propagate handle data for resource variables
  packed_tensor = ctx.pack_eager_tensors(tensors)
  if handle_data is not None:
    packed_tensor._handle_data = handle_data  # pylint: disable=protected-access

  def grad_fun(_):
    raise ValueError(
        "Computing gradients through pack_eager_tensors is not supported.")

  record.record_operation("pack_eager_tensors", [packed_tensor], tensors,
                          grad_fun)

  return packed_tensor


@profiler_trace.trace_wrapper("convert_to_tensor")
def convert_to_tensor(
    value,
    dtype=None,
    name=None,
    as_ref=False,
    preferred_dtype=None,
    dtype_hint=None,
    # TODO(b/268347915): Remove argument.
    ctx=None,  # pylint: disable=unused-argument
    accepted_result_types=(tensor_lib.Tensor,),
) -> Union[EagerTensor, SymbolicTensor]:
  """Implementation of the public convert_to_tensor."""
  # TODO(b/142518781): Fix all call-sites and remove redundant arg
  preferred_dtype = preferred_dtype or dtype_hint
  return tensor_conversion_registry.convert(
      value, dtype, name, as_ref, preferred_dtype, accepted_result_types
  )


internal_convert_to_tensor: Callable[
    ..., Union[EagerTensor, SymbolicTensor]] = convert_to_tensor


def internal_convert_n_to_tensor(
    values,
    dtype=None,
    name=None,
    as_ref=False,
    preferred_dtype=None,
    # TODO(b/268347915): Remove argument.
    ctx=None) -> list[Union[EagerTensor, SymbolicTensor]]:  # pylint: disable=unused-argument
  """Converts `values` to a list of `Tensor` objects.

  Args:
    values: A list of objects that can be consumed by `tf.convert_to_tensor()`.
    dtype: (Optional.) The required `DType` of the returned `Tensor` objects.
    name: (Optional.) A name prefix to used when a new `Tensor` is created, in
      which case element `i` will be given the name `name + '_' + i`.
    as_ref: True if the caller wants the results as ref tensors.
    preferred_dtype: Optional element type for the returned tensors, used when
      dtype is None. In some cases, a caller may not have a dtype in mind when
      converting to a tensor, so preferred_dtype can be used as a soft
      preference.  If the conversion to `preferred_dtype` is not possible, this
      argument has no effect.
    ctx: Unused. Present for API backwards compatibility.

  Returns:
    A list of `Tensor` and/or `IndexedSlices` objects.

  Raises:
    TypeError: If no conversion function is registered for an element in
      `values`.
    RuntimeError: If a registered conversion function returns an invalid
      value.
  """
  if not isinstance(values, collections_abc.Sequence):
    raise TypeError("values must be a sequence.")
  ret = []
  for i, value in enumerate(values):
    n = None if name is None else "%s_%d" % (name, i)
    ret.append(
        convert_to_tensor(
            value,
            dtype=dtype,
            name=n,
            as_ref=as_ref,
            preferred_dtype=preferred_dtype))
  return ret


def convert_n_to_tensor(
    values, dtype=None, name=None, preferred_dtype=None
) ->  list[Union[EagerTensor, SymbolicTensor]]:
  """Converts `values` to a list of `Tensor` objects.

  Args:
    values: A list of objects that can be consumed by `tf.convert_to_tensor()`.
    dtype: (Optional.) The required `DType` of the returned `Tensor` objects.
    name: (Optional.) A name prefix to used when a new `Tensor` is created, in
      which case element `i` will be given the name `name + '_' + i`.
    preferred_dtype: Optional element type for the returned tensors, used when
      dtype is None. In some cases, a caller may not have a dtype in mind when
      converting to a tensor, so preferred_dtype can be used as a soft
      preference.  If the conversion to `preferred_dtype` is not possible, this
      argument has no effect.

  Returns:
    A list of `Tensor` and/or `IndexedSlices` objects.

  Raises:
    TypeError: If no conversion function is registered for an element in
      `values`.
    RuntimeError: If a registered conversion function returns an invalid
      value.
  """
  return internal_convert_n_to_tensor(
      values=values,
      dtype=dtype,
      name=name,
      preferred_dtype=preferred_dtype,
      as_ref=False)


def convert_to_tensor_or_composite(
    value, dtype=None, name=None
) -> Union[EagerTensor, SymbolicTensor, composite_tensor.CompositeTensor]:
  """Converts the given object to a `Tensor` or `CompositeTensor`.

  If `value` is a `CompositeTensor` it is returned unmodified. Otherwise, it
  is converted to a `Tensor` using `convert_to_tensor()`.

  Args:
    value: A `CompositeTensor` or an object that can be consumed by
      `convert_to_tensor()`.
    dtype: (Optional.) The required `DType` of the returned `Tensor` or
      `CompositeTensor`.
    name: (Optional.) A name to use if a new `Tensor` is created.

  Returns:
    A `Tensor` or `CompositeTensor`, based on `value`.

  Raises:
    ValueError: If `dtype` does not match the element type of `value`.
  """
  return internal_convert_to_tensor_or_composite(
      value=value, dtype=dtype, name=name, as_ref=False)


def internal_convert_to_tensor_or_composite(
    value, dtype=None,
    name=None,
    as_ref=False
) -> Union[EagerTensor, SymbolicTensor, composite_tensor.CompositeTensor]:
  """Converts the given object to a `Tensor` or `CompositeTensor`.

  If `value` is a `CompositeTensor` it is returned unmodified.  Otherwise, it
  is converted to a `Tensor` using `convert_to_tensor()`.

  Args:
    value: A `CompositeTensor`, or an object that can be consumed by
      `convert_to_tensor()`.
    dtype: (Optional.) The required `DType` of the returned `Tensor` or
      `CompositeTensor`.
    name: (Optional.) A name to use if a new `Tensor` is created.
    as_ref: True if the caller wants the results as ref tensors.

  Returns:
    A `Tensor` or `CompositeTensor`, based on `value`.

  Raises:
    ValueError: If `dtype` does not match the element type of `value`.
  """
  if isinstance(value, composite_tensor.CompositeTensor):
    value_dtype = getattr(value, "dtype", None)
    if dtype and not dtypes.as_dtype(dtype).is_compatible_with(value_dtype):
      raise ValueError(f"Tensor conversion dtype mismatch. "
                       f"Requested dtype is {dtypes.as_dtype(dtype).name}, "
                       f"Tensor has dtype {value.dtype.name}: {value!r}")
    return value
  else:
    return convert_to_tensor(
        value,
        dtype=dtype,
        name=name,
        as_ref=as_ref,
        accepted_result_types=(
            tensor_lib.Tensor, composite_tensor.CompositeTensor))


def internal_convert_n_to_tensor_or_composite(
    values,
    dtype=None,
    name=None,
    as_ref=False
) -> list[Union[
    EagerTensor, SymbolicTensor, composite_tensor.CompositeTensor, type(None)]]:
  """Converts `values` to a list of `Tensor` or `CompositeTensor` objects.

  Any `CompositeTensor` objects in `values` are returned unmodified.

  Args:
    values: A list of `None`, `CompositeTensor`, or objects that can be consumed
      by `convert_to_tensor()`.
    dtype: (Optional.) The required `DType` of the returned `Tensor`s or
      `CompositeTensor`s.
    name: (Optional.) A name prefix to used when a new `Tensor` is created, in
      which case element `i` will be given the name `name + '_' + i`.
    as_ref: True if the caller wants the results as ref tensors.

  Returns:
    A list of `Tensor`, `CompositeTensor`, and/or `None` objects.

  Raises:
    TypeError: If no conversion function is registered for an element in
      `values`.
    RuntimeError: If a registered conversion function returns an invalid
      value.
  """
  if not isinstance(values, collections_abc.Sequence):
    raise TypeError("values must be a sequence.")
  ret = []
  for i, value in enumerate(values):
    if value is None:
      ret.append(value)
    else:
      n = None if name is None else "%s_%d" % (name, i)
      ret.append(
          internal_convert_to_tensor_or_composite(
              value, dtype=dtype, name=n, as_ref=as_ref))
  return ret


def convert_n_to_tensor_or_composite(
    values, dtype=None, name=None
) -> list[Union[
    EagerTensor, SymbolicTensor, composite_tensor.CompositeTensor, type(None)]]:
  """Converts `values` to a list of `Output` or `CompositeTensor` objects.

  Any `CompositeTensor` objects in `values` are returned unmodified.

  Args:
    values: A list of `None`, `CompositeTensor``, or objects that can be
      consumed by `convert_to_tensor()`.
    dtype: (Optional.) The required `DType` of the returned `Tensor`s or
      `CompositeTensor`s.
    name: (Optional.) A name prefix to used when a new `Tensor` is created, in
      which case element `i` will be given the name `name + '_' + i`.

  Returns:
    A list of `Tensor` and/or `CompositeTensor` objects.

  Raises:
    TypeError: If no conversion function is registered for an element in
      `values`.
    RuntimeError: If a registered conversion function returns an invalid
      value.
  """
  return internal_convert_n_to_tensor_or_composite(
      values=values, dtype=dtype, name=name, as_ref=False)


def _device_string(dev_spec) -> str:
  if pydev.is_device_spec(dev_spec):
    return dev_spec.to_string()
  else:
    return dev_spec


def _NodeDef(op_type, name, attrs=None) -> node_def_pb2.NodeDef:
  """Create a NodeDef proto.

  Args:
    op_type: Value for the "op" attribute of the NodeDef proto.
    name: Value for the "name" attribute of the NodeDef proto.
    attrs: Dictionary where the key is the attribute name (a string)
      and the value is the respective "attr" attribute of the NodeDef proto (an
      AttrValue).

  Returns:
    A node_def_pb2.NodeDef protocol buffer.
  """
  node_def = node_def_pb2.NodeDef(op=compat.as_bytes(op_type),
                                  name=compat.as_bytes(name))
  if attrs:
    for k, v in attrs.items():
      node_def.attr[k].CopyFrom(v)
  return node_def


# Copied from core/framework/node_def_util.cc
# TODO(mrry,josh11b): Consolidate this validation in C++ code.
_VALID_OP_NAME_REGEX: Pattern[str] = re.compile(
    r"^[A-Za-z0-9.][A-Za-z0-9_.\\/>-]*$")
_VALID_SCOPE_NAME_REGEX: Pattern[str] = re.compile(
    r"^[A-Za-z0-9_.\\/>-]*$")


@tf_export("__internal__.create_c_op", v1=[])
@traceback_utils.filter_traceback
def _create_c_op(graph,
                 node_def,
                 inputs,
                 control_inputs,
                 op_def=None,
                 extract_traceback=True) -> pywrap_tf_session.TF_Operation:
  """Creates a TF_Operation.

  Args:
    graph: a `Graph`.
    node_def: `node_def_pb2.NodeDef` for the operation to create.
    inputs: A flattened list of `Tensor`s. This function handles grouping
      tensors into lists as per attributes in the `node_def`.
    control_inputs: A list of `Operation`s to set as control dependencies.
    op_def: Optional. `op_def_pb2.OpDef` for the operation to create. If not
      specified, is looked up from the `graph` using `node_def.op`.
    extract_traceback: if True, extract the current Python traceback to the
      TF_Operation.

  Returns:
    A wrapped TF_Operation*.
  """
  if op_def is None:
    op_def = graph.op_def_for_type(node_def.op)  # pylint: disable=protected-access
  # TODO(skyewm): op_def_library.apply_op() flattens the incoming inputs.
  # Refactor so we don't have to do this here.
  inputs = _reconstruct_sequence_inputs(op_def, inputs, node_def.attr)
  # pylint: disable=protected-access
  with graph._c_graph.get() as c_graph:
    op_desc = pywrap_tf_session.TF_NewOperation(c_graph,
                                                compat.as_str(node_def.op),
                                                compat.as_str(node_def.name))
  if node_def.device:
    pywrap_tf_session.TF_SetDevice(op_desc, compat.as_str(node_def.device))
  # Add inputs
  for op_input in inputs:
    if isinstance(op_input, (list, tuple)):
      pywrap_tf_session.TF_AddInputList(op_desc,
                                        [t._as_tf_output() for t in op_input])
    else:
      pywrap_tf_session.TF_AddInput(op_desc, op_input._as_tf_output())

  # Add control inputs
  for control_input in control_inputs:
    pywrap_tf_session.TF_AddControlInput(op_desc, control_input._c_op)
  # pylint: enable=protected-access

  # Add attrs
  for name, attr_value in node_def.attr.items():
    serialized = attr_value.SerializeToString()
    # TODO(skyewm): this creates and deletes a new TF_Status for every attr.
    # It might be worth creating a convenient way to re-use the same status.
    pywrap_tf_session.TF_SetAttrValueProto(op_desc, compat.as_str(name),
                                           serialized)

  try:
    c_op = pywrap_tf_session.TF_FinishOperation(op_desc)
  except errors.InvalidArgumentError as e:
    # Convert to ValueError for backwards compatibility.
    raise ValueError(e.message)

  # Record the current Python stack trace as the creating stacktrace of this
  # TF_Operation.
  if extract_traceback:
    pywrap_tf_session.TF_SetOpStackTrace(
        c_op, tf_stack.extract_stack(stacklevel=3)
    )

  return c_op


@tf_export("Operation")
class Operation(pywrap_tf_session.PyOperation):
  """Represents a graph node that performs computation on tensors.

  An `Operation` is a node in a `tf.Graph` that takes zero or more `Tensor`
  objects as input, and produces zero or more `Tensor` objects as output.
  Objects of type `Operation` are created by calling a Python op constructor
  (such as `tf.matmul`) within a `tf.function` or under a `tf.Graph.as_default`
  context manager.

  For example, within a `tf.function`, `c = tf.matmul(a, b)` creates an
  `Operation` of type "MatMul" that takes tensors `a` and `b` as input, and
  produces `c` as output.

  If a `tf.compat.v1.Session` is used, an `Operation` of a `tf.Graph` can be
  executed by passing it to `tf.Session.run`. `op.run()` is a shortcut for
  calling `tf.compat.v1.get_default_session().run(op)`.
  """

  @classmethod
  def from_node_def(
      cls: type[OperationType],
      node_def,
      g,
      inputs=None,
      output_types=None,
      control_inputs=None,
      input_types=None,
      original_op=None,
      op_def=None,
  ) -> OperationType:
    r"""Creates an `Operation`.

    NOTE: This constructor validates the name of the `Operation` (passed
    as `node_def.name`). Valid `Operation` names match the following
    regular expression:

        [A-Za-z0-9.][A-Za-z0-9_.\\-/]*

    Args:
      node_def: `node_def_pb2.NodeDef`.  `NodeDef` for the `Operation`. Used for
        attributes of `node_def_pb2.NodeDef`, typically `name`, `op`, and
        `device`.  The `input` attribute is irrelevant here as it will be
        computed when generating the model.
      g: `Graph`. The parent graph.
      inputs: list of `Tensor` objects. The inputs to this `Operation`.
      output_types: list of `DType` objects.  List of the types of the `Tensors`
        computed by this operation.  The length of this list indicates the
        number of output endpoints of the `Operation`.
      control_inputs: list of operations or tensors from which to have a control
        dependency.
      input_types: List of `DType` objects representing the types of the tensors
        accepted by the `Operation`.  By default uses `[x.dtype.base_dtype for x
        in inputs]`.  Operations that expect reference-typed inputs must specify
        these explicitly.
      original_op: Optional. Used to associate the new `Operation` with an
        existing `Operation` (for example, a replica with the op that was
        replicated).
      op_def: Optional. The `op_def_pb2.OpDef` proto that describes the op type
        that this `Operation` represents.

    Raises:
      TypeError: if control inputs are not Operations or Tensors,
        or if `node_def` is not a `NodeDef`,
        or if `g` is not a `Graph`,
        or if `inputs` are not tensors,
        or if `inputs` and `input_types` are incompatible.
      ValueError: if the `node_def` name is not valid.

    Returns:
      Operation object.
    """
    if not isinstance(g, Graph):
      raise TypeError(f"Argument g must be a Graph. "
                      f"Received an instance of type {type(g)}")

    if not isinstance(node_def, node_def_pb2.NodeDef):
      raise TypeError(f"Argument node_def must be a NodeDef. "
                      f"Received an instance of type: {type(node_def)}.")
    if node_def.ByteSize() >= (1 << 31) or node_def.ByteSize() < 0:
      raise ValueError(
          f"Cannot create a tensor proto whose content is larger than 2GB. "
          f"Size of tensor is {node_def.ByteSize()} bytes.")

    # TODO(mdan): This does not belong here. Graph::AddNode should handle it.
    if not _VALID_OP_NAME_REGEX.match(node_def.name):
      raise ValueError(
          f"`{node_def.name}` is not a valid node name. "
          f"Accepted names conform to Regex /{_VALID_OP_NAME_REGEX}/")

    # FIXME(b/225400189): output_types is unused. Consider remove it from
    # the argument list.
    del output_types

    if inputs is None:
      inputs = []
    elif not isinstance(inputs, list):
      raise TypeError(f"Argument inputs shall be a list of Tensors. "
                      f"Received an instance of type {type(inputs)}")
    for a in inputs:
      if not isinstance(a, tensor_lib.Tensor):
        raise TypeError(f"Items of argument inputs shall be Tensor. "
                        f"Received an instance of type {type(a)}.")
    if input_types is None:
      input_types = [i.dtype.base_dtype for i in inputs]
    else:
      if not all(
          x.is_compatible_with(i.dtype) for i, x in zip(inputs, input_types)):
        raise TypeError("In op '%s', input types (%s) are not compatible "
                        "with expected types (%s)" %
                        (node_def.name, [i.dtype for i in inputs], input_types))

    # Build the list of control inputs.
    control_input_ops = []
    if control_inputs:
      for c in control_inputs:
        control_op = None
        if isinstance(c, Operation):
          control_op = c
        elif isinstance(c, (tensor_lib.Tensor, internal.IndexedSlices)):
          control_op = c.op
        else:
          raise TypeError(f"Control input must be an Operation, "
                          f"a Tensor, or IndexedSlices. "
                          f"Received an instance of type {type(c)}.")
        control_input_ops.append(control_op)

    # Initialize c_op from node_def and other inputs
    c_op = _create_c_op(g, node_def, inputs, control_input_ops, op_def=op_def)
    self = Operation(c_op, SymbolicTensor)
    self._init(g)

    self._original_op = original_op

    # Post process for control flows.
    self._control_flow_post_processing(input_tensors=inputs)

    return self

  @classmethod
  def _from_c_op(cls: type[OperationType], c_op, g) -> OperationType:
    """Create an Operation from a TF_Operation.

    For internal use only: This is useful for creating Operation for ops
    indirectly created by C API methods, e.g. the ops created by
    TF_ImportGraphDef.

    Args:
      c_op: a TF_Operation.
      g: A Graph.

    Returns:
      an Operation object.
    """
    self = Operation(c_op, SymbolicTensor)
    self._init(g)
    return self

  def _init(self, graph: "Graph") -> None:
    """Initializes Operation from a TF_Operation."""
    self.graph = graph
    self._original_op = None

    # This will be set by self.inputs.
    self._inputs_val = None

    # List of _UserDevSpecs holding code location of device context manager
    # invocations and the users original argument to them.
    self._device_code_locations = None
    # Dict mapping op name to file and line information for op colocation
    # context managers.
    self._colocation_code_locations = None
    self._control_flow_context = self.graph._get_control_flow_context()  # pylint: disable=protected-access

    # Gradient function for this op. There are three ways to specify gradient
    # function, and first available gradient gets used, in the following order.
    # 1. self._gradient_function
    # 2. Gradient name registered by "_gradient_op_type" attribute.
    # 3. Gradient name registered by op.type.
    self._gradient_function = None

    self._init_outputs()
    self._id_value = self.graph._add_op(self)  # pylint: disable=protected-access

  def _control_flow_post_processing(self, input_tensors=None) -> None:
    """Add this op to its control flow context.

    This may add new ops and change this op's inputs. self.inputs must be
    available before calling this method.

    Args:
      input_tensors: (Optional.) A list of `Tensors` corresponding to the inputs
        of this op, which should be equivalent to `self.inputs`. Pass this
        argument to avoid evaluating `self.inputs` unnecessarily.
    """
    if input_tensors is None:
      input_tensors = self.inputs
    for input_tensor in input_tensors:
      control_flow_util.CheckInputFromValidContext(self, input_tensor.op)
    if self._control_flow_context is not None:
      self._control_flow_context.AddOp(self)

  def colocation_groups(self) -> list[bytes]:
    """Returns the list of colocation groups of the op."""
    default_colocation_group = [compat.as_bytes("loc:@%s" % self.name)]
    try:
      class_attr = self.get_attr("_class")
    except ValueError:
      # This op has no explicit colocation group, so it is itself its
      # own root of a colocation group.
      return default_colocation_group

    attr_groups = [
        class_name for class_name in class_attr
        if class_name.startswith(b"loc:@")
    ]

    # If there are no colocation groups in the explicit _class field,
    # return the default colocation group.
    return attr_groups if attr_groups else default_colocation_group

  def values(self) -> tuple[Any, ...]:
    """DEPRECATED: Use outputs."""
    return tuple(self.outputs)

  def _get_control_flow_context(self):
    """Returns the control flow context of this op.

    Returns:
      A context object.
    """
    return self._control_flow_context

  def _set_control_flow_context(self, ctx) -> None:
    """Sets the current control flow context of this op.

    Args:
      ctx: a context object.
    """
    self._control_flow_context = ctx

  @property
  def _id(self) -> int:
    """The unique integer id of this operation."""
    return self._id_value

  @property
  def device(self) -> str:
    """The name of the device to which this op has been assigned, if any.

    Returns:
      The string name of the device to which this op has been
      assigned, or an empty string if it has not been assigned to a
      device.
    """
    return pywrap_tf_session.TF_OperationDevice(self._c_op)

  @property
  def _device_assignments(self) -> list[traceable_stack.TraceableObject]:
    """Code locations for device context managers active at op creation.

    This property will return a list of traceable_stack.TraceableObject
    instances where .obj is a string representing the assigned device
    (or information about the function that would be applied to this op
    to compute the desired device) and the filename and lineno members
    record the location of the relevant device context manager.

    For example, suppose file_a contained these lines:

      file_a.py:
        15: with tf.device('/gpu:0'):
        16:   node_b = tf.constant(4, name='NODE_B')

    Then a TraceableObject t_obj representing the device context manager
    would have these member values:

      t_obj.obj -> '/gpu:0'
      t_obj.filename = 'file_a.py'
      t_obj.lineno = 15

    and node_b.op._device_assignments would return the list [t_obj].

    Returns:
      [str: traceable_stack.TraceableObject, ...] as per this method's
      description, above.
    """
    return self._device_code_locations or []

  @property
  def _colocation_dict(self) -> dict[str, traceable_stack.TraceableObject]:
    """Code locations for colocation context managers active at op creation.

    This property will return a dictionary for which the keys are nodes with
    which this Operation is colocated, and for which the values are
    traceable_stack.TraceableObject instances.  The TraceableObject instances
    record the location of the relevant colocation context manager but have the
    "obj" field set to None to prevent leaking private data.

    For example, suppose file_a contained these lines:

      file_a.py:
        14: node_a = tf.constant(3, name='NODE_A')
        15: with tf.compat.v1.colocate_with(node_a):
        16:   node_b = tf.constant(4, name='NODE_B')

    Then a TraceableObject t_obj representing the colocation context manager
    would have these member values:

      t_obj.obj -> None
      t_obj.filename = 'file_a.py'
      t_obj.lineno = 15

    and node_b.op._colocation_dict would return the dictionary

      { 'NODE_A': t_obj }

    Returns:
      {str: traceable_stack.TraceableObject} as per this method's description,
      above.
    """
    locations_dict = self._colocation_code_locations or {}
    return locations_dict.copy()

  @property
  def _output_types(self) -> list[int]:
    """List this operation's output types.

    Returns:
      List of the types of the Tensors computed by this operation.
      Each element in the list is an integer whose value is one of
      the TF_DataType enums defined in pywrap_tf_session.h
      The length of this list indicates the number of output endpoints
      of the operation.
    """
    num_outputs = pywrap_tf_session.TF_OperationNumOutputs(self._c_op)
    output_types = [
        int(pywrap_tf_session.TF_OperationOutputType(self._tf_output(i)))
        for i in range(num_outputs)
    ]

    return output_types

  def _set_device(self, device) -> None:  # pylint: disable=redefined-outer-name
    """Set the device of this operation.

    Args:
      device: string or device..  The device to set.
    """
    self._set_device_from_string(compat.as_str(_device_string(device)))

  def _update_input(self, index, tensor) -> None:
    """Update the input to this operation at the given index.

    NOTE: This is for TF internal use only. Please don't use it.

    Args:
      index: the index of the input to update.
      tensor: the Tensor to be used as the input at the given index.

    Raises:
      TypeError: if tensor is not a Tensor,
        or if input tensor type is not convertible to dtype.
      ValueError: if the Tensor is from a different graph.
    """
    if not isinstance(tensor, tensor_lib.Tensor):
      raise TypeError("tensor must be a Tensor: %s" % tensor)

    _assert_same_graph(self, tensor)

    # Reset cached inputs.
    self._inputs_val = None
    with self.graph._c_graph.get() as c_graph:  # pylint: disable=protected-access
      pywrap_tf_session.UpdateEdge(
          c_graph,
          tensor._as_tf_output(),  # pylint: disable=protected-access
          self._tf_input(index))

  def _add_while_inputs(self, tensors) -> None:
    """See AddWhileInputHack in python_api.h.

    NOTE: This is for TF internal use only. Please don't use it.

    Args:
      tensors: list of Tensors

    Raises:
      TypeError: if tensor is not a Tensor,
        or if input tensor type is not convertible to dtype.
      ValueError: if the Tensor is from a different graph.
    """
    with self.graph._c_graph.get() as c_graph:  # pylint: disable=protected-access
      for tensor in tensors:
        if not isinstance(tensor, tensor_lib.Tensor):
          raise TypeError("tensor must be a Tensor: %s" % tensor)
        _assert_same_graph(self, tensor)

        # Reset cached inputs.
        self._inputs_val = None
        pywrap_tf_session.AddWhileInputHack(
            c_graph,  # pylint: disable=protected-access
            tensor._as_tf_output(),  # pylint: disable=protected-access
            self._c_op)

  def __str__(self) -> str:
    return str(self.node_def)

  def __repr__(self) -> str:
    return "<tf.Operation '%s' type=%s>" % (self.name, self.type)

  def __tf_tensor__(self, dtype=None, name=None) -> NoReturn:
    """Raises a helpful error."""
    raise TypeError("can't convert Operation '{}' to Tensor".format(self.name))

  @property
  def inputs(self) -> Sequence[tensor_lib.Tensor]:
    """The sequence of `Tensor` objects representing the data inputs of this op."""
    if self._inputs_val is None:
      # pylint: disable=protected-access
      self._inputs_val = tuple(
          self.graph._get_tensor_by_tf_output(i)
          for i in pywrap_tf_session.GetOperationInputs(self._c_op))
      # pylint: enable=protected-access
    return self._inputs_val

  @property
  def _input_types(self) -> list[dtypes.DType]:
    num_inputs = pywrap_tf_session.TF_OperationNumInputs(self._c_op)
    input_types = [
        dtypes.as_dtype(
            pywrap_tf_session.TF_OperationInputType(self._tf_input(i)))
        for i in range(num_inputs)
    ]
    return input_types

  @property
  def traceback(self):
    """Returns the call stack from when this operation was constructed."""
    # FIXME(b/225423591): This object contains a dangling reference if _c_op
    # goes out of scope.
    return pywrap_tf_session.TF_OperationGetStackTrace(self._c_op)

  @property
  def node_def(self) -> node_def_pb2.NodeDef:
    return node_def_pb2.NodeDef.FromString(self._node_def)

  @property
  def op_def(self) -> op_def_pb2.OpDef:
    return op_def_pb2.OpDef.FromString(self._op_def)

  def _set_attr(self, attr_name, attr_value) -> None:
    """Private method used to set an attribute in the node_def."""
    buf = pywrap_tf_session.TF_NewBufferFromString(
        compat.as_bytes(attr_value.SerializeToString()))
    try:
      self._set_attr_with_buf(attr_name, buf)
    finally:
      pywrap_tf_session.TF_DeleteBuffer(buf)

  def _set_attr_with_buf(self, attr_name, attr_buf) -> None:
    """Set an attr in the node_def with a pre-allocated buffer."""
    with self.graph._c_graph.get() as c_graph:  # pylint: disable=protected-access
      # pylint: disable=protected-access
      pywrap_tf_session.SetAttr(c_graph, self._c_op, attr_name, attr_buf)
      # pylint: enable=protected-access

  def _set_func_attr(self, attr_name, func_name) -> None:
    """Private method used to set a function attribute in the node_def."""
    func = attr_value_pb2.NameAttrList(name=func_name)
    self._set_attr(attr_name, attr_value_pb2.AttrValue(func=func))

  def _set_func_list_attr(self, attr_name, func_names) -> None:
    """Private method used to set a list(function) attribute in the node_def."""
    funcs = [attr_value_pb2.NameAttrList(name=func_name)
             for func_name in func_names]
    funcs_list = attr_value_pb2.AttrValue.ListValue(func=funcs)
    self._set_attr(attr_name, attr_value_pb2.AttrValue(list=funcs_list))

  def _set_type_list_attr(self, attr_name, data_types) -> None:
    """Private method used to set a list(type) attribute in the node_def."""
    if not data_types:
      return
    if isinstance(data_types[0], dtypes.DType):
      data_types = [dt.as_datatype_enum for dt in data_types]
    types_list = attr_value_pb2.AttrValue.ListValue(type=data_types)
    self._set_attr(attr_name, attr_value_pb2.AttrValue(list=types_list))

  def _set_shape_list_attr(self, attr_name, shapes) -> None:
    """Private method used to set a list(shape) attribute in the node_def."""
    shapes = [s.as_proto() for s in shapes]
    shapes_list = attr_value_pb2.AttrValue.ListValue(shape=shapes)
    self._set_attr(attr_name, attr_value_pb2.AttrValue(list=shapes_list))

  def _clear_attr(self, attr_name) -> None:
    """Private method used to clear an attribute in the node_def."""
    with self.graph._c_graph.get() as c_graph:  # pylint: disable=protected-access
      # pylint: disable=protected-access
      pywrap_tf_session.ClearAttr(c_graph, self._c_op, attr_name)
      # pylint: enable=protected-access

  def get_attr(self, name):
    """Returns the value of the attr of this op with the given `name`.

    Args:
      name: The name of the attr to fetch.

    Returns:
      The value of the attr, as a Python object.

    Raises:
      ValueError: If this op does not have an attr with the given `name`.
    """
    fields = ("s", "i", "f", "b", "type", "shape", "tensor", "func")
    try:
      with c_api_util.tf_buffer() as buf:   # pytype: disable=wrong-arg-count
        pywrap_tf_session.TF_OperationGetAttrValueProto(self._c_op, name, buf)
        data = pywrap_tf_session.TF_GetBuffer(buf)
    except errors.InvalidArgumentError as e:
      # Convert to ValueError for backwards compatibility.
      raise ValueError(e.message)
    x = attr_value_pb2.AttrValue()
    x.ParseFromString(data)

    oneof_value = x.WhichOneof("value")
    if oneof_value is None:
      return []
    if oneof_value == "list":
      for f in fields:
        if getattr(x.list, f):
          if f == "type":
            return [dtypes.as_dtype(t) for t in x.list.type]
          else:
            return list(getattr(x.list, f))
      return []
    if oneof_value == "type":
      return dtypes.as_dtype(x.type)
    assert oneof_value in fields, "Unsupported field type in " + str(x)
    return getattr(x, oneof_value)

  def _get_attr_type(self, name) -> dtypes.DType:
    """Returns the `DType` value of the attr of this op with the given `name`."""
    try:
      dtype_enum = pywrap_tf_session.TF_OperationGetAttrType(self._c_op, name)
      return _DTYPES_INTERN_TABLE[dtype_enum]
    except errors.InvalidArgumentError as e:
      # Convert to ValueError for backwards compatibility.
      raise ValueError(e.message)

  def _get_attr_bool(self, name) -> bool:
    """Returns the `bool` value of the attr of this op with the given `name`."""
    try:
      return pywrap_tf_session.TF_OperationGetAttrBool(self._c_op, name)
    except errors.InvalidArgumentError as e:
      # Convert to ValueError for backwards compatibility.
      raise ValueError(e.message)

  def _get_attr_int(self, name) -> int:
    """Returns the `int` value of the attr of this op with the given `name`."""
    try:
      return pywrap_tf_session.TF_OperationGetAttrInt(self._c_op, name)
    except errors.InvalidArgumentError as e:
      # Convert to ValueError for backwards compatibility.
      raise ValueError(e.message)

  def experimental_set_type(self, type_proto) -> None:
    """Sets the corresponding node's `experimental_type` field.

    See the description of `NodeDef.experimental_type` for more info.

    Args:
      type_proto: A FullTypeDef proto message. The root type_if of this object
        must be `TFT_PRODUCT`, even for ops which only have a singlre return
        value.
    """
    with self.graph._c_graph.get() as c_graph:  # pylint: disable=protected-access
      if (type_proto.type_id
          not in (full_type_pb2.TFT_UNSET, full_type_pb2.TFT_PRODUCT)):
        raise ValueError("error setting the type of ", self.name,
                         ": expected TFT_UNSET or TFT_PRODUCT, got ",
                         type_proto.type_id)
      with c_api_util.tf_buffer(type_proto.SerializeToString()) as serialized:
        pywrap_tf_session.SetFullType(c_graph, self._c_op, serialized)  # pylint:disable=protected-access

  def run(self, feed_dict=None, session=None) -> None:
    """Runs this operation in a `Session`.

    Calling this method will execute all preceding operations that
    produce the inputs needed for this operation.

    *N.B.* Before invoking `Operation.run()`, its graph must have been
    launched in a session, and either a default session must be
    available, or `session` must be specified explicitly.

    Args:
      feed_dict: A dictionary that maps `Tensor` objects to feed values. See
        `tf.Session.run` for a description of the valid feed values.
      session: (Optional.) The `Session` to be used to run to this operation. If
        none, the default session will be used.
    """
    _run_using_default_session(self, feed_dict, self.graph, session)

gradient_registry: registry.Registry
_gradient_registry: registry.Registry
# TODO(b/185395742): Clean up usages of _gradient_registry
gradient_registry = _gradient_registry = registry.Registry("gradient")


@tf_export("RegisterGradient")
class RegisterGradient(object):
  """A decorator for registering the gradient function for an op type.

  This decorator is only used when defining a new op type. For an op
  with `m` inputs and `n` outputs, the gradient function is a function
  that takes the original `Operation` and `n` `Tensor` objects
  (representing the gradients with respect to each output of the op),
  and returns `m` `Tensor` objects (representing the partial gradients
  with respect to each input of the op).

  For example, assuming that operations of type `"Sub"` take two
  inputs `x` and `y`, and return a single output `x - y`, the
  following gradient function would be registered:

  ```python
  @tf.RegisterGradient("Sub")
  def _sub_grad(unused_op, grad):
    return grad, tf.negative(grad)
  ```

  The decorator argument `op_type` is the string type of an
  operation. This corresponds to the `OpDef.name` field for the proto
  that defines the operation.
  """

  __slots__ = ["_op_type"]

  def __init__(self, op_type):
    """Creates a new decorator with `op_type` as the Operation type.

    Args:
      op_type: The string type of an operation. This corresponds to the
        `OpDef.name` field for the proto that defines the operation.

    Raises:
      TypeError: If `op_type` is not string.
    """
    if not isinstance(op_type, str):
      raise TypeError("op_type must be a string")
    self._op_type = op_type

  def __call__(self, f: _T) -> _T:
    """Registers the function `f` as gradient function for `op_type`."""
    gradient_registry.register(f, self._op_type)
    return f


@deprecation.deprecated_endpoints("NotDifferentiable", "NoGradient")
@tf_export("no_gradient", v1=["no_gradient", "NotDifferentiable", "NoGradient"])
def no_gradient(op_type: str) -> None:
  """Specifies that ops of type `op_type` is not differentiable.

  This function should *not* be used for operations that have a
  well-defined gradient that is not yet implemented.

  This function is only used when defining a new op type. It may be
  used for ops such as `tf.size()` that are not differentiable.  For
  example:

  ```python
  tf.no_gradient("Size")
  ```

  The gradient computed for 'op_type' will then propagate zeros.

  For ops that have a well-defined gradient but are not yet implemented,
  no declaration should be made, and an error *must* be thrown if
  an attempt to request its gradient is made.

  Args:
    op_type: The string type of an operation. This corresponds to the
      `OpDef.name` field for the proto that defines the operation.

  Raises:
    TypeError: If `op_type` is not a string.

  """
  if not isinstance(op_type, str):
    raise TypeError("op_type must be a string")
  gradient_registry.register(None, op_type)


# Aliases for the old names, will be eventually removed.
NoGradient: Callable[[str], None] = no_gradient
NotDifferentiable: Callable[[str], None] = no_gradient


def get_gradient_function(op):
  """Returns the function that computes gradients for "op"."""
  if not op.inputs:
    return None

  gradient_function = op._gradient_function  # pylint: disable=protected-access
  if gradient_function:
    return gradient_function

  try:
    op_type = op.get_attr("_gradient_op_type")
  except ValueError:
    op_type = op.type
  return gradient_registry.lookup(op_type)


def set_shape_and_handle_data_for_outputs(_) -> None:
  """No op. TODO(b/74620627): Remove this."""
  pass


class OpStats(object):
  """A holder for statistics about an operator.

  This class holds information about the resource requirements for an op,
  including the size of its weight parameters on-disk and how many FLOPS it
  requires to execute forward inference.

  If you define a new operation, you can create a function that will return a
  set of information about its usage of the CPU and disk space when serialized.
  The function itself takes a Graph object that's been set up so you can call
  methods like get_tensor_by_name to help calculate the results, and a NodeDef
  argument.

  """

  __slots__ = ["_statistic_type", "_value"]

  def __init__(self, statistic_type, value=None) -> None:
    """Sets up the initial placeholders for the statistics."""
    self.statistic_type = statistic_type
    self.value = value

  @property
  def statistic_type(self):
    return self._statistic_type

  @statistic_type.setter
  def statistic_type(self, statistic_type):
    self._statistic_type = statistic_type

  @property
  def value(self):
    return self._value

  @value.setter
  def value(self, value):
    self._value = value

  def __iadd__(self: OpStatsType, other: OpStatsType) -> OpStatsType:
    if other.statistic_type != self.statistic_type:
      raise ValueError("Can't add an OpStat of type %s to one of %s." %
                       (self.statistic_type, other.statistic_type))
    if self.value is None:
      self.value = other.value
    elif other.value is not None:
      self._value += other.value  # pytype: disable=attribute-error
    return self


_stats_registry: registry.Registry = registry.Registry("statistical functions")


class RegisterStatistics(object):
  """A decorator for registering the statistics function for an op type.

  This decorator can be defined for an op type so that it gives a
  report on the resources used by an instance of an operator, in the
  form of an OpStats object.

  Well-known types of statistics include these so far:

  - flops: When running a graph, the bulk of the computation happens doing
    numerical calculations like matrix multiplications. This type allows a node
    to return how many floating-point operations it takes to complete. The
    total number of FLOPs for a graph is a good guide to its expected latency.

  You can add your own statistics just by picking a new type string, registering
  functions for the ops you care about, and then calling get_stats_for_node_def.

  If a statistic for an op is registered multiple times, a KeyError will be
  raised.

  Since the statistics is counted on a per-op basis. It is not suitable for
  model parameters (capacity), which is expected to be counted only once, even
  if it is shared by multiple ops. (e.g. RNN)

  For example, you can define a new metric called doohickey for a Foo operation
  by placing this in your code:

  ```python
  @ops.RegisterStatistics("Foo", "doohickey")
  def _calc_foo_bojangles(unused_graph, unused_node_def):
    return ops.OpStats("doohickey", 20)
  ```

  Then in client code you can retrieve the value by making this call:

  ```python
  doohickey = ops.get_stats_for_node_def(graph, node_def, "doohickey")
  ```

  If the NodeDef is for an op with a registered doohickey function, you'll get
  back the calculated amount in doohickey.value, or None if it's not defined.

  """

  __slots__ = ["_op_type", "_statistic_type"]

  def __init__(self, op_type, statistic_type) -> None:
    """Saves the `op_type` as the `Operation` type."""
    if not isinstance(op_type, str):
      raise TypeError("op_type must be a string.")
    if "," in op_type:
      raise TypeError("op_type must not contain a comma.")
    self._op_type = op_type
    if not isinstance(statistic_type, str):
      raise TypeError("statistic_type must be a string.")
    if "," in statistic_type:
      raise TypeError("statistic_type must not contain a comma.")
    self._statistic_type = statistic_type

  def __call__(self, f: _T) -> _T:
    """Registers "f" as the statistics function for "op_type"."""
    _stats_registry.register(f, self._op_type + "," + self._statistic_type)
    return f


def get_stats_for_node_def(graph, node, statistic_type) -> Any:
  """Looks up the node's statistics function in the registry and calls it.

  This function takes a Graph object and a NodeDef from a GraphDef, and if
  there's an associated statistics method, calls it and returns a result. If no
  function has been registered for the particular node type, it returns an empty
  statistics object.

  Args:
    graph: A Graph object that's been set up with the node's graph.
    node: A NodeDef describing the operator.
    statistic_type: A string identifying the statistic we're interested in.

  Returns:
    An OpStats object containing information about resource usage.
  """

  try:
    stats_func = _stats_registry.lookup(node.op + "," + statistic_type)
    result = stats_func(graph, node)
  except LookupError:
    result = OpStats(statistic_type)
  return result


def name_from_scope_name(name) -> str:
  """Returns the name of an op given the name of its scope.

  Args:
    name: the name of the scope.

  Returns:
    the name of the op (equal to scope name minus any trailing slash).
  """
  return name[:-1] if (name and name[-1] == "/") else name


_MUTATION_LOCK_GROUP: int = 0
_SESSION_RUN_LOCK_GROUP: int = 1


@tf_contextlib.contextmanager
def resource_creator_scope(resource_type, resource_creator) -> Iterator[None]:
  with get_default_graph()._resource_creator_scope(resource_type,  # pylint: disable=protected-access
                                                   resource_creator):
    yield


@tf_export("Graph")
class Graph(pywrap_tf_session.PyGraph):
  """A TensorFlow computation, represented as a dataflow graph.

  Graphs are used by `tf.function`s to represent the function's computations.
  Each graph contains a set of `tf.Operation` objects, which represent units of
  computation; and `tf.Tensor` objects, which represent the units of data that
  flow between operations.

  ### Using graphs directly (deprecated)

  A `tf.Graph` can be constructed and used directly without a `tf.function`, as
  was required in TensorFlow 1, but this is deprecated and it is recommended to
  use a `tf.function` instead. If a graph is directly used, other deprecated
  TensorFlow 1 classes are also required to execute the graph, such as a
  `tf.compat.v1.Session`.

  A default graph can be registered with the `tf.Graph.as_default` context
  manager. Then, operations will be added to the graph instead of being executed
  eagerly. For example:

  ```python
  g = tf.Graph()
  with g.as_default():
    # Define operations and tensors in `g`.
    c = tf.constant(30.0)
    assert c.graph is g
  ```

  `tf.compat.v1.get_default_graph()` can be used to obtain the default graph.

  Important note: This class *is not* thread-safe for graph construction. All
  operations should be created from a single thread, or external
  synchronization must be provided. Unless otherwise specified, all methods
  are not thread-safe.

  A `Graph` instance supports an arbitrary number of "collections"
  that are identified by name. For convenience when building a large
  graph, collections can store groups of related objects: for
  example, the `tf.Variable` uses a collection (named
  `tf.GraphKeys.GLOBAL_VARIABLES`) for
  all variables that are created during the construction of a graph. The caller
  may define additional collections by specifying a new name.
  """

  def __init__(self) -> None:
    """Creates a new, empty Graph."""
    super().__init__()
    # Protects core state that can be returned via public accessors.
    # Thread-safety is provided on a best-effort basis to support buggy
    # programs, and is not guaranteed by the public `tf.Graph` API.
    #
    # NOTE(mrry): This does not protect the various stacks. A warning will
    # be reported if these are used from multiple threads
    self._lock = threading.RLock()
    # The group lock synchronizes Session.run calls with methods that create
    # and mutate ops (e.g. Graph.create_op()). This synchronization is
    # necessary because it's illegal to modify an operation after it's been run.
    # The group lock allows any number of threads to mutate ops at the same time
    # but if any modification is going on, all Session.run calls have to wait.
    # Similarly, if one or more Session.run calls are going on, all mutate ops
    # have to wait until all Session.run calls have finished.
    self._group_lock = lock_util.GroupLock(num_groups=2)
    # Maps a name used in the graph to the next id to use for that name.
    self._names_in_use = {}
    self._stack_state_is_thread_local = False
    self._thread_local = threading.local()
    # Functions that will be applied to choose a device if none is specified.
    # In TF2.x or after switch_to_thread_local(),
    # self._thread_local._device_function_stack is used instead.
    self._graph_device_function_stack = traceable_stack.TraceableStack()
    # Default original_op applied to new ops.
    self._default_original_op = None
    # Current control flow context. It could be either CondContext or
    # WhileContext defined in ops/control_flow_ops.py
    self._control_flow_context = None
    # A new node will depend of the union of all of the nodes in the stack.
    # In TF2.x or after switch_to_thread_local(),
    # self._thread_local._control_dependencies_stack is used instead.
    self._graph_control_dependencies_stack = []
    # Arbitrary collections of objects.
    self._collections = {}
    # The graph-level random seed
    self._seed = None
    # A dictionary of attributes that should be applied to all ops.
    self._attr_scope_map = {}
    # A map from op type to the kernel label that should be used.
    self._op_to_kernel_label_map = {}
    # A map from op type to an alternative op type that should be used when
    # computing gradients.
    self._gradient_override_map = {}
    # A map from op type to a gradient function that should be used instead.
    self._gradient_function_map = {}
    # True if the graph is considered "finalized".  In that case no
    # new operations can be added.
    self._finalized = False
    # Functions defined in the graph
    self._functions = collections.OrderedDict()
    # Default GraphDef versions
    self._graph_def_versions = versions_pb2.VersionDef(
        producer=versions.GRAPH_DEF_VERSION,
        min_consumer=versions.GRAPH_DEF_VERSION_MIN_CONSUMER)
    self._building_function = False
    # Stack of colocate_with ops. In TF2.x or after switch_to_thread_local(),
    # self._thread_local._colocation_stack is used instead.
    self._graph_colocation_stack = traceable_stack.TraceableStack()
    # Set of tensors that are dangerous to feed!
    self._unfeedable_tensors = object_identity.ObjectIdentitySet()
    # Set of operations that are dangerous to fetch!
    self._unfetchable_ops = set()
    # A map of tensor handle placeholder to tensor dtype.
    self._handle_feeders = {}
    # A map from tensor handle to its read op.
    self._handle_readers = {}
    # A map from tensor handle to its move op.
    self._handle_movers = {}
    # A map from tensor handle to its delete op.
    self._handle_deleters = {}
    # Allow optimizers and other objects to pseudo-uniquely key graphs (this key
    # will be shared when defining function graphs, for example, so optimizers
    # being called inside function definitions behave as if they were seeing the
    # actual outside graph).
    self._graph_key = "graph-key-%d/" % (uid(),)
    # A string with the last reduction method passed to
    # losses.compute_weighted_loss(), or None.
    # Backward compatibility with optimizer V1 use cases.
    self._last_loss_reduction = None
    # Required only for backward compatibility with optimizer V1 use cases.
    self._is_loss_scaled_by_optimizer = False
    self._container = ""

    # The current AutomaticControlDependencies context manager.
    self.experimental_acd_manager = None
    # Set to True if this graph is being built in an
    # AutomaticControlDependencies context.
    # Deprecated: use acd_manager instead.
    self._add_control_dependencies = False

    # Cache for OpDef protobufs retrieved via the C API.
    self._op_def_cache = {}
    # Cache for constant results of `reduced_shape()`. The keys are pairs of
    # tuples: (input_shape_tuple, reduction_indices_tuple), and the values
    # are pairs of tuples: (output_shape_kept_dims, tile_scaling).
    self._reduced_shape_cache = {}

    if tf2.enabled():
      self.switch_to_thread_local()

  # `Graph` now _is_ the C graph, but we have many places that manually attempt
  # to manipulate the _c_graph object. Leave these accessors here until these
  # are cleaned up.
  @property
  def _c_graph(self):
    return self

  def __enter__(self: GraphType) -> GraphType:
    return self

  def __exit__(self, *args) -> None:
    return

  def get(self: GraphType) -> GraphType:
    return self

  # Note: this method is private because the API of tf.Graph() is public and
  # frozen, and this functionality is still not ready for public visibility.
  @tf_contextlib.contextmanager
  def _variable_creator_scope(self, creator, priority=100) -> Iterator[None]:
    """Scope which defines a variable creation function.

    Args:
      creator: A callable taking `next_creator` and `kwargs`. See the
        `tf.variable_creator_scope` docstring.
      priority: Creators with a higher `priority` are called first. Within the
        same priority, creators are called inner-to-outer.

    Yields:
      `_variable_creator_scope` is a context manager with a side effect, but
      doesn't return a value.

    Raises:
      RuntimeError: If variable creator scopes are not properly nested.
    """
    # This step keeps a reference to the existing stack, and it also initializes
    # self._thread_local._variable_creator_stack if it doesn't exist yet.
    old = self._variable_creator_stack
    new = list(old)
    new.append((priority, creator))
    # Sorting is stable, so we'll put higher-priority creators later in the list
    # but otherwise maintain registration order.
    new.sort(key=lambda item: item[0])
    self._thread_local._variable_creator_stack = new  # pylint: disable=protected-access
    try:
      yield
    finally:
      if self._thread_local._variable_creator_stack is not new:  # pylint: disable=protected-access
        raise RuntimeError(
            "Exiting variable_creator_scope without proper nesting.")
      self._thread_local._variable_creator_stack = old  # pylint: disable=protected-access

  # TODO(b/192405401): unify resource_creator_scope with variable_creator_scope.
  # pylint: disable=protected-access
  @tf_contextlib.contextmanager
  def _resource_creator_scope(self, resource_type, creator) -> Iterator[None]:
    """Scope which defines a resource creation function used by some resource.

    The resource should be a subclass of CapturableResource with a class method
    `cls._resource_type`, the output of which is what the `resource_type`
    argument should be. By default, `cls._resource_type` returns the class name,
    `cls.__name__`. Given a scope, creators being added with the same
    `resource_type` argument will be composed together to apply to all classes
    with this `_resource_type`.


    `creator` is expected to be a function with the following signature:

    ```
      def resource_creator(next_creator, *a, **kwargs)
    ```

    The creator is supposed to eventually call the next_creator to create an
    instance if it does want to create an instance and not call
    the class initialization method directly. This helps make creators
    composable. A creator may choose to create multiple instances, return
    already existing instances, or simply register that an instance was created
    and defer to the next creator in line. Creators can also modify keyword
    arguments seen by the next creators.

    Valid keyword arguments in `kwargs` depends on the specific resource
    class. For StaticHashTable, this may be:
    * initializer: The table initializer to use.
    * default_value: The value to use if a key is missing in the table.
    * name: Optional name for the table, default to None.


    Args:
      resource_type: the output of the resource class's `_resource_type` method.
      creator: the passed creator for the resource.

    Yields:
      A scope in which the creator is active

    Raises:
      RuntimeError: If resource_creator_scope is existed without proper nesting.
    """
    # This step keeps a reference to the existing stack, and it also initializes
    # self._thread_local._variable_creator_stack if it doesn't exist yet.
    old = self._resource_creator_stack
    new = copy.deepcopy(old)
    if isinstance(resource_type, (list, tuple)):
      for r in resource_type:
        new[r].append(creator)
    else:
      new[resource_type].append(creator)
    self._thread_local._resource_creator_stack = new
    try:
      yield
    finally:
      if self._thread_local._resource_creator_stack is not new:
        raise RuntimeError(
            "Exiting resource_creator_scope without proper nesting.")
      self._thread_local._resource_creator_stack = old

  @property
  def _resource_creator_stack(self) -> dict[str, list[Callable[..., Any]]]:
    if not hasattr(self._thread_local, "_resource_creator_stack"):
      self._thread_local._resource_creator_stack = collections.defaultdict(list)
    return self._thread_local._resource_creator_stack

  @_resource_creator_stack.setter
  def _resource_creator_stack(
      self,
      resource_creator_stack: dict[str, list[Callable[..., Any]]],
  ) -> None:
    self._thread_local._resource_creator_stack = resource_creator_stack
  # pylint: enable=protected-access

  # Note: this method is private because the API of tf.Graph() is public and
  # frozen, and this functionality is still not ready for public visibility.
  @property
  def _variable_creator_stack(self) -> list[tuple[int, Callable[..., Any]]]:
    if not hasattr(self._thread_local, "_variable_creator_stack"):
      self._thread_local._variable_creator_stack = []  # pylint: disable=protected-access

    # This previously returned a copy of the stack instead of the stack itself,
    # to guard against accidental mutation. Consider, however, code that wants
    # to save and restore the variable creator stack:
    #     def f():
    #       original_stack = graph._variable_creator_stack
    #       graph._variable_creator_stack = new_stack
    #       ...  # Some code
    #       graph._variable_creator_stack = original_stack
    #
    # And lets say you have some code that calls this function with some
    # variable_creator:
    #     def g():
    #       with variable_scope.variable_creator_scope(creator):
    #         f()
    # When exiting the variable creator scope, it would see a different stack
    # object than it expected leading to a "Exiting variable_creator_scope
    # without proper nesting" error.
    return self._thread_local._variable_creator_stack  # pylint: disable=protected-access

  @_variable_creator_stack.setter
  def _variable_creator_stack(
      self,
      variable_creator_stack: list[tuple[int, Callable[..., Any]]],
  ) -> None:
    self._thread_local._variable_creator_stack = variable_creator_stack  # pylint: disable=protected-access

  def _check_not_finalized(self) -> None:
    """Check if the graph is finalized.

    Raises:
      RuntimeError: If the graph finalized.
    """
    if self._finalized:
      raise RuntimeError("Graph is finalized and cannot be modified.")

  @property
  def graph_def_versions(self) -> versions_pb2.VersionDef:
    # pylint: disable=line-too-long
    """The GraphDef version information of this graph.

    For details on the meaning of each version, see
    [`GraphDef`](https://www.tensorflow.org/code/tensorflow/core/framework/graph.proto).

    Returns:
      A `VersionDef`.
    """
    return versions_pb2.VersionDef.FromString(self._version_def)

  @property
  def seed(self) -> Optional[int]:
    """The graph-level random seed of this graph."""
    return self._seed

  @seed.setter
  def seed(self, seed: int) -> None:
    self._seed = seed

  @property
  def finalized(self) -> bool:
    """True if this graph has been finalized."""
    return self._finalized

  def finalize(self) -> None:
    """Finalizes this graph, making it read-only.

    After calling `g.finalize()`, no new operations can be added to
    `g`.  This method is used to ensure that no operations are added
    to a graph when it is shared between multiple threads, for example
    when using a `tf.compat.v1.train.QueueRunner`.
    """
    self._finalized = True

  def _unsafe_unfinalize(self) -> None:
    """Opposite of `finalize`.

    Internal interface.

    NOTE: Unfinalizing a graph could have negative impact on performance,
    especially in a multi-threaded environment.  Unfinalizing a graph
    when it is in use by a Session may lead to undefined behavior. Ensure
    that all sessions using a graph are closed before calling this method.
    """
    self._finalized = False

  def _get_control_flow_context(self):
    """Returns the current control flow context.

    Returns:
      A context object.
    """
    return self._control_flow_context

  def _set_control_flow_context(self, ctx) -> None:
    """Sets the current control flow context.

    Args:
      ctx: a context object.
    """
    self._control_flow_context = ctx

  def _copy_functions_to_graph_def(self, graph_def, starting_bytesize) -> None:
    """If this graph contains functions, copy them to `graph_def`."""
    bytesize = starting_bytesize
    for f in self._functions.values():
      bytesize += f.cached_definition.ByteSize()
      if bytesize >= (1 << 31) or bytesize < 0:
        raise ValueError("GraphDef cannot be larger than 2GB.")
      graph_def.library.function.extend([f.cached_definition])
      if getattr(f, "grad_func_name", None):
        grad_def = function_pb2.GradientDef()
        grad_def.function_name = f.name
        grad_def.gradient_func = f.grad_func_name
        graph_def.library.gradient.extend([grad_def])

  def _as_graph_def(
      self, from_version=None, add_shapes=False, use_pybind11_proto=False,
  ) -> tuple[graph_pb2.GraphDef, int]:
    # pylint: disable=line-too-long
    """Returns a serialized `GraphDef` representation of this graph.

    The serialized `GraphDef` can be imported into another `Graph`
    (using `tf.import_graph_def`) or used with the
    [C++ Session API](https://chromium.googlesource.com/external/github.com/tensorflow/tensorflow/+/r0.10/tensorflow/g3doc/api_docs/cc/index.md).

    This method is thread-safe.

    Args:
      from_version: Optional.  If this is set, returns a `GraphDef` containing
        only the nodes that were added to this graph since its `version`
        property had the given value.
      add_shapes: If true, adds an "_output_shapes" list attr to each node with
        the inferred shapes of each of its outputs.
      use_pybind11_proto: If true, uses the c++ pybind11_proto api to get the
        GraphDef proto directly from c++, instead of through a TF buffer.

    Returns:
      A tuple containing a
      [`GraphDef`](https://www.tensorflow.org/code/tensorflow/core/framework/graph.proto)
      protocol buffer, and the version of the graph to which that
      `GraphDef` corresponds.

    Raises:
      ValueError: If the `graph_def` would be too large.

    """
    # pylint: enable=line-too-long
    with self._lock:
      if use_pybind11_proto:
        with self._c_graph.get() as c_graph:
          graph = graph_pb2.GraphDef()
          graph.CopyFrom(pywrap_tf_session.TF_GraphToGraphDefPybind(c_graph))
      else:
        with c_api_util.tf_buffer() as buf:   # pytype: disable=wrong-arg-count
          with self._c_graph.get() as c_graph:
            pywrap_tf_session.TF_GraphToGraphDef(c_graph, buf)
            data = pywrap_tf_session.TF_GetBuffer(buf)
        graph = graph_pb2.GraphDef()
        graph.ParseFromString(compat.as_bytes(data))
      # Strip the experimental library field iff it's empty.
      if not graph.library.function:
        graph.ClearField("library")

      if add_shapes:
        for node in graph.node:
          op = self._get_operation_by_name(node.name)
          if op.outputs:
            node.attr["_output_shapes"].list.shape.extend(
                [output.get_shape().as_proto() for output in op.outputs])
        for function_def in graph.library.function:
          defined_function = self._functions[function_def.signature.name]
          try:
            func_graph = defined_function.graph
          except AttributeError:
            # _DefinedFunction doesn't have a graph, _EagerDefinedFunction
            # does. Both rely on ops.py, so we can't really isinstance check
            # them.
            continue
          input_shapes = function_def.attr["_input_shapes"]
          try:
            func_graph_inputs = func_graph.inputs
          except AttributeError:
            continue
          # TODO(b/141471245): Fix the inconsistency when inputs of func graph
          # are appended during gradient computation of while/cond.
          assert len(input_shapes.list.shape) in [0, len(func_graph_inputs)]
          # If the function_def has inputs already filled out, skip this step.
          if not input_shapes.list.shape:
            for input_tensor, arg_def in zip(func_graph_inputs,
                                             function_def.signature.input_arg):
              input_shapes.list.shape.add().CopyFrom(
                  input_tensor.get_shape().as_proto())
              if input_tensor.dtype == dtypes.resource:
                _copy_handle_data_to_arg_def(input_tensor, arg_def)

          for output_tensor, arg_def in zip(func_graph.outputs,
                                            function_def.signature.output_arg):
            if output_tensor.dtype == dtypes.resource:
              _copy_handle_data_to_arg_def(output_tensor, arg_def)

          for node in function_def.node_def:
            try:
              op = func_graph.get_operation_by_name(node.name)
            except KeyError:
              continue
            outputs = op.outputs

            if op.type == "StatefulPartitionedCall":
              # Filter out any extra outputs (possibly added by function
              # backpropagation rewriting).
              num_outputs = len(node.attr["Tout"].list.type)
              outputs = outputs[:num_outputs]

            node.attr["_output_shapes"].list.shape.extend(
                [output.get_shape().as_proto() for output in outputs])

    return graph, self.version

  def as_graph_def(
      self, from_version=None, add_shapes=False, use_pybind11_proto=False
  ) -> graph_pb2.GraphDef:
    # pylint: disable=line-too-long
    """Returns a serialized `GraphDef` representation of this graph.

    The serialized `GraphDef` can be imported into another `Graph`
    (using `tf.import_graph_def`) or used with the
    [C++ Session API](../../api_docs/cc/index.md).

    This method is thread-safe.

    Args:
      from_version: Optional.  If this is set, returns a `GraphDef` containing
        only the nodes that were added to this graph since its `version`
        property had the given value.
      add_shapes: If true, adds an "_output_shapes" list attr to each node with
        the inferred shapes of each of its outputs.
      use_pybind11_proto: If true, If true, uses the c++ pybind11_proto api to
        get the GraphDef proto directly from c++, instead of through a TF
        buffer. See https://github.com/pybind/pybind11_protobuf for reference.

    Returns:
      A
      [`GraphDef`](https://www.tensorflow.org/code/tensorflow/core/framework/graph.proto)
      protocol buffer.

    Raises:
      ValueError: If the `graph_def` would be too large.
    """
    # pylint: enable=line-too-long
    if is_oss:
      use_pybind11_proto = False
    result, _ = self._as_graph_def(
        from_version, add_shapes, use_pybind11_proto=use_pybind11_proto
    )
    return result

  def _is_function(self, name) -> bool:
    """Tests whether 'name' is registered in this graph's function library.

    Args:
      name: string op name.

    Returns:
      bool indicating whether or not 'name' is registered in function library.
    """
    return compat.as_str(name) in self._functions

  def _get_function(self, name):
    """Returns the function definition for 'name'.

    Args:
      name: string function name.

    Returns:
      The function def proto.
    """
    return self._functions.get(compat.as_str(name), None)

  def _add_function_recursive(self, function, overwrite=False) -> None:
    """Adds function to the graph including other functions in its graph."""

    if self._is_function(function.name):
      if overwrite:
        self._remove_function(function.name)
        self._add_function(function)
    else:
      self._add_function(function)

    if hasattr(function, "children"):
      for f in function.children:  # pylint: disable=protected-access
        if self._is_function(f.name):
          if overwrite:
            self._remove_function(f.name)
            self._add_function(f)
        else:
          self._add_function(f)

  def _add_function(self, function) -> None:
    """Adds a function to the graph.

    After the function has been added, you can call to the function by
    passing the function name in place of an op name to
    `Graph.create_op()`.

    Args:
      function: A `_DefinedFunction` object.

    Raises:
      ValueError: if another function is defined with the same name.
    """
    self._check_not_finalized()

    name = function.name
    # Sanity checks on gradient definition for deprecated _DefinedFunction.
    if getattr(function, "grad_func_name", None) and getattr(
        function, "python_grad_func", None
    ):
      raise ValueError("Gradient defined twice for function %s" % name)

    # Add function to graph
    # pylint: disable=protected-access
    with self._c_graph.get() as c_graph:
      with function._c_func.get() as func:
        if getattr(function, "_grad_func", None):
          # For deprecated _DefinedFunction.
          with function._grad_func._c_func.get() as gradient:
            pywrap_tf_session.TF_GraphCopyFunction(c_graph, func, gradient)
        else:
          pywrap_tf_session.TF_GraphCopyFunction(c_graph, func, None)
    # pylint: enable=protected-access

    self._functions[compat.as_str(name)] = function

    # Need a new-enough consumer to support the functions we add to the graph.
    if self._graph_def_versions.min_consumer < 12:
      self._graph_def_versions.min_consumer = 12

  def _remove_function(self, name) -> None:
    self._check_not_finalized()
    if not self._is_function(name):
      raise ValueError(f"Function {name!r} is not found in {self!r}.")

    with self._c_graph.get() as c_graph:
      pywrap_tf_session.TF_GraphRemoveFunction(c_graph, compat.as_bytes(name))
      del self._functions[compat.as_str(name)]

  @property
  def building_function(self) -> bool:
    """Returns True iff this graph represents a function."""
    return self._building_function

  # Helper functions to create operations.
  @deprecated_args(None,
                   "Shapes are always computed; don't use the compute_shapes "
                   "as it has no effect.", "compute_shapes")
  @traceback_utils.filter_traceback
  def create_op(
      self,
      op_type,
      inputs,
      dtypes=None,  # pylint: disable=redefined-outer-name
      input_types=None,
      name=None,
      attrs=None,
      op_def=None,
      compute_shapes=True,
      compute_device=True) -> "Operation":
    """Creates an `Operation` in this graph.

    This is a low-level interface for creating an `Operation`. Most
    programs will not call this method directly, and instead use the
    Python op constructors, such as `tf.constant()`, which add ops to
    the default graph.

    Args:
      op_type: The `Operation` type to create. This corresponds to the
        `OpDef.name` field for the proto that defines the operation.
      inputs: A list of `Tensor` objects that will be inputs to the `Operation`.
      dtypes: (Optional) A list of `DType` objects that will be the types of the
        tensors that the operation produces.
      input_types: (Optional.) A list of `DType`s that will be the types of the
        tensors that the operation consumes. By default, uses the base `DType`
        of each input in `inputs`. Operations that expect reference-typed inputs
        must specify `input_types` explicitly.
      name: (Optional.) A string name for the operation. If not specified, a
        name is generated based on `op_type`.
      attrs: (Optional.) A dictionary where the key is the attribute name (a
        string) and the value is the respective `attr` attribute of the
        `NodeDef` proto that will represent the operation (an `AttrValue`
        proto).
      op_def: (Optional.) The `OpDef` proto that describes the `op_type` that
        the operation will have.
      compute_shapes: (Optional.) Deprecated. Has no effect (shapes are always
        computed).
      compute_device: (Optional.) If True, device functions will be executed to
        compute the device property of the Operation.

    Raises:
      TypeError: if any of the inputs is not a `Tensor`.
      ValueError: if colocation conflicts with existing device assignment.

    Returns:
      An `Operation` object.
    """
    del compute_shapes
    for idx, a in enumerate(inputs):
      if not isinstance(a, tensor_lib.Tensor):
        raise TypeError("Input #%d is not a tensor: %s" % (idx, a))
    return self._create_op_internal(op_type, inputs, dtypes, input_types, name,
                                    attrs, op_def, compute_device)

  def _create_op_internal(
      self,
      op_type,
      inputs,
      dtypes=None,  # pylint: disable=redefined-outer-name
      input_types=None,
      name=None,
      attrs=None,
      op_def=None,
      compute_device=True) -> "Operation":
    """Creates an `Operation` in this graph.

    Implements `Graph.create_op()` without the overhead of the dep
