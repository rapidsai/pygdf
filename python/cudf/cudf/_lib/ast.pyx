# Copyright (c) 2021, NVIDIA CORPORATION.

from enum import Enum
import ast

from cudf.core.column_accessor import ColumnAccessor
from cudf.core.dataframe import DataFrame

from cython.operator cimport dereference
from cudf._lib.cpp.types cimport size_type
from libcpp.memory cimport make_shared, shared_ptr, unique_ptr
from libcpp.utility cimport move
from cudf._lib.ast cimport underlying_type_ast_operator
from cudf._lib.column cimport Column
from cudf._lib.cpp.column.column cimport column
from cudf._lib.table cimport Table

cimport cudf._lib.cpp.ast as libcudf_ast


class ASTOperator(Enum):
    ADD = libcudf_ast.ast_operator.ADD
    SUB = libcudf_ast.ast_operator.SUB
    MUL = libcudf_ast.ast_operator.MUL
    DIV = libcudf_ast.ast_operator.DIV
    TRUE_DIV = libcudf_ast.ast_operator.TRUE_DIV
    FLOOR_DIV = libcudf_ast.ast_operator.FLOOR_DIV
    MOD = libcudf_ast.ast_operator.MOD
    PYMOD = libcudf_ast.ast_operator.PYMOD
    POW = libcudf_ast.ast_operator.POW
    EQUAL = libcudf_ast.ast_operator.EQUAL
    NOT_EQUAL = libcudf_ast.ast_operator.NOT_EQUAL
    LESS = libcudf_ast.ast_operator.LESS
    GREATER = libcudf_ast.ast_operator.GREATER
    LESS_EQUAL = libcudf_ast.ast_operator.LESS_EQUAL
    GREATER_EQUAL = libcudf_ast.ast_operator.GREATER_EQUAL
    BITWISE_AND = libcudf_ast.ast_operator.BITWISE_AND
    BITWISE_OR = libcudf_ast.ast_operator.BITWISE_OR
    BITWISE_XOR = libcudf_ast.ast_operator.BITWISE_XOR
    LOGICAL_AND = libcudf_ast.ast_operator.LOGICAL_AND
    LOGICAL_OR = libcudf_ast.ast_operator.LOGICAL_OR
    # Unary operators
    IDENTITY = libcudf_ast.ast_operator.IDENTITY
    SIN = libcudf_ast.ast_operator.SIN
    COS = libcudf_ast.ast_operator.COS
    TAN = libcudf_ast.ast_operator.TAN
    ARCSIN = libcudf_ast.ast_operator.ARCSIN
    ARCCOS = libcudf_ast.ast_operator.ARCCOS
    ARCTAN = libcudf_ast.ast_operator.ARCTAN
    SINH = libcudf_ast.ast_operator.SINH
    COSH = libcudf_ast.ast_operator.COSH
    TANH = libcudf_ast.ast_operator.TANH
    ARCSINH = libcudf_ast.ast_operator.ARCSINH
    ARCCOSH = libcudf_ast.ast_operator.ARCCOSH
    ARCTANH = libcudf_ast.ast_operator.ARCTANH
    EXP = libcudf_ast.ast_operator.EXP
    LOG = libcudf_ast.ast_operator.LOG
    SQRT = libcudf_ast.ast_operator.SQRT
    CBRT = libcudf_ast.ast_operator.CBRT
    CEIL = libcudf_ast.ast_operator.CEIL
    FLOOR = libcudf_ast.ast_operator.FLOOR
    ABS = libcudf_ast.ast_operator.ABS
    RINT = libcudf_ast.ast_operator.RINT
    BIT_INVERT = libcudf_ast.ast_operator.BIT_INVERT
    NOT = libcudf_ast.ast_operator.NOT


class TableReference(Enum):
    LEFT = libcudf_ast.table_reference.LEFT
    RIGHT = libcudf_ast.table_reference.RIGHT
    OUTPUT = libcudf_ast.table_reference.OUTPUT


cdef class Node:
    cdef libcudf_ast.node * _get_ptr(self):
        return self.c_node.get()


cdef class Literal(Node):
    def __cinit__(self, value):
        # TODO: Generalize this to other types of literals.
        cdef float val = value
        self.c_scalar = make_shared[numeric_scalar[float]](val, True)
        self.c_obj = make_shared[libcudf_ast.literal](
            <numeric_scalar[float] &>dereference(self.c_scalar))
        self.c_node = <shared_ptr[libcudf_ast.node]> self.c_obj


cdef class ColumnReference(Node):
    def __cinit__(self, index):
        cdef size_type idx = index
        self.c_obj = make_shared[libcudf_ast.column_reference](idx)
        self.c_node = <shared_ptr[libcudf_ast.node]> self.c_obj


cdef class Expression(Node):
    def __cinit__(self, op, Node left, Node right=None):
        # This awkward double casting appears to be the only way to get Cython
        # to generate valid C++ that doesn't try to apply the shift operator
        # directly to values of the enum (which is invalid).
        cdef libcudf_ast.ast_operator op_value = <libcudf_ast.ast_operator> (
            <underlying_type_ast_operator> op.value)

        if right is None:
            self.c_obj = make_shared[libcudf_ast.expression](
                op_value,
                <const libcudf_ast.node &>dereference(left._get_ptr())
            )
        else:
            self.c_obj = make_shared[libcudf_ast.expression](
                op_value,
                <const libcudf_ast.node &>dereference(left._get_ptr()),
                <const libcudf_ast.node &>dereference(right._get_ptr())
            )

        self.c_node = <shared_ptr[libcudf_ast.node]> self.c_obj


cdef evaluate_expression_internal(Table values, Expression expr):
    result_data = ColumnAccessor()
    cdef unique_ptr[column] col = libcudf_ast.compute_column(
        values.view(),
        <const libcudf_ast.expression>dereference(expr.c_obj.get())
    )
    result_data['result'] = Column.from_unique_ptr(move(col))
    result_table = Table(data=result_data)
    return DataFrame._from_table(result_table)


def evaluate_expression(df, expr):
    return evaluate_expression_internal(df, expr)


# This dictionary encodes the mapping from Python AST operators to their cudf
# counterparts.
python_cudf_ast_map = {
    # TODO: Mapping TBD for commented out operators.
    # Binary operators
    ast.Add: ASTOperator.ADD,
    ast.Sub: ASTOperator.SUB,
    ast.Mult: ASTOperator.MUL,
    ast.Div: ASTOperator.DIV,
    # ast.True: ASTOperator.TRUE_DIV,
    ast.FloorDiv: ASTOperator.FLOOR_DIV,
    ast.Mod: ASTOperator.PYMOD,
    # ast.Pymod: ASTOperator.PYMOD,
    ast.Pow: ASTOperator.POW,
    ast.Eq: ASTOperator.EQUAL,
    ast.NotEq: ASTOperator.NOT_EQUAL,
    ast.Lt: ASTOperator.LESS,
    ast.Gt: ASTOperator.GREATER,
    ast.LtE: ASTOperator.LESS_EQUAL,
    ast.GtE: ASTOperator.GREATER_EQUAL,
    ast.BitAnd: ASTOperator.BITWISE_AND,
    ast.BitOr: ASTOperator.BITWISE_OR,
    ast.BitXor: ASTOperator.BITWISE_XOR,
    ast.And: ASTOperator.LOGICAL_AND,
    ast.Or: ASTOperator.LOGICAL_OR,
    # Unary operators
    # ast.Identity: ASTOperator.IDENTITY,
    # ast.Sin: ASTOperator.SIN,
    # ast.Cos: ASTOperator.COS,
    # ast.Tan: ASTOperator.TAN,
    # ast.Arcsin: ASTOperator.ARCSIN,
    # ast.Arccos: ASTOperator.ARCCOS,
    # ast.Arctan: ASTOperator.ARCTAN,
    # ast.Sinh: ASTOperator.SINH,
    # ast.Cosh: ASTOperator.COSH,
    # ast.Tanh: ASTOperator.TANH,
    # ast.Arcsinh: ASTOperator.ARCSINH,
    # ast.Arccosh: ASTOperator.ARCCOSH,
    # ast.Arctanh: ASTOperator.ARCTANH,
    # ast.Exp: ASTOperator.EXP,
    # ast.Log: ASTOperator.LOG,
    # ast.Sqrt: ASTOperator.SQRT,
    # ast.Cbrt: ASTOperator.CBRT,
    # ast.Ceil: ASTOperator.CEIL,
    # ast.Floor: ASTOperator.FLOOR,
    # ast.Abs: ASTOperator.ABS,
    # ast.Rint: ASTOperator.RINT,
    # ast.Bit: ASTOperator.BIT_INVERT,
    # ast.Not: ASTOperator.NOT,
}


cpdef ast_visit(node, df, list stack, list temporaries):
    # Base cases: Name
    if isinstance(node, ast.Name):
        temporaries.append(ColumnReference(df.columns.get_loc(node.id) + 1))
    else:
        for field, value in ast.iter_fields(node):
            if isinstance(value, ast.UnaryOp):
                ast_visit(value.operand, df, stack, temporaries)
                op = python_cudf_ast_map[type(value.op)]
                stack.append(Expression(op, temporaries[-1]))
            elif isinstance(value, ast.BinOp):
                ast_visit(value.left, df, stack, temporaries)
                ast_visit(value.right, df, stack, temporaries)
                op = python_cudf_ast_map[type(value.op)]
                stack.append(Expression(
                    ASTOperator.ADD, temporaries[-2], temporaries[-1]))
            elif isinstance(value, list):
                for item in value:
                    if isinstance(item, ast.AST):
                        ast_visit(item, df, stack, temporaries)
            elif isinstance(value, ast.AST):
                ast_visit(value, df, stack, temporaries)


def make_and_evaluate_expression(expr, df):
    """Create a cudf evaluable expression from a string and evaluate it."""
    # Important: both make and evaluate must be coupled to guarantee that the
    # temporaries created (the owning ColumnReferences and Literals) remain in
    # scope.
    stack = []
    temporaries = []
    ast_visit(ast.parse(expr), df, stack, temporaries)
    return evaluate_expression(df, stack[-1])
