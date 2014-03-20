#!/usr/bin/env cython
# cython: boundscheck=False
# cython: wraparound=False
# cython: cdivision=True
# coding: utf-8
#
# Copyright (C) 2013 Radim Rehurek <me@radimrehurek.com>
# Licensed under the GNU LGPL v2.1 - http://www.gnu.org/licenses/lgpl.html

import cython
import numpy as np
cimport numpy as np

from libc.math cimport exp
from libc.string cimport memset

from cpython cimport PyCObject_AsVoidPtr
from scipy.linalg.blas import fblas

REAL = np.float32
ctypedef np.float32_t REAL_t

DEF MAX_SENTENCE_LEN = 1000

ctypedef void (*scopy_ptr) (const int *N, const float *X, const int *incX, float *Y, const int *incY) nogil
ctypedef void (*saxpy_ptr) (const int *N, const float *alpha, const float *X, const int *incX, float *Y, const int *incY) nogil
ctypedef float (*sdot_ptr) (const int *N, const float *X, const int *incX, const float *Y, const int *incY) nogil
ctypedef double (*dsdot_ptr) (const int *N, const float *X, const int *incX, const float *Y, const int *incY) nogil
ctypedef double (*snrm2_ptr) (const int *N, const float *X, const int *incX) nogil
ctypedef void (*sscal_ptr) (const int *N, const float *alpha, const float *X, const int *incX) nogil

ctypedef void (* fast_sentence_sg_hs_ptr) (
    const np.uint32_t *word_point, const np.uint8_t *word_code, const int codelen,
    REAL_t *syn0, REAL_t *syn1, const int size,
    const np.uint32_t word2_index, const REAL_t alpha, REAL_t *work) nogil

ctypedef void (* fast_sentence_sg_neg_ptr) (
    const int pos, const int negative, np.uint32_t *table,
    REAL_t *syn0, REAL_t *syn1neg, const int size, const np.uint32_t word_index,
    const np.uint32_t word2_index, const REAL_t alpha, REAL_t *work, 
    np.uint32_t *random_numbers) nogil

ctypedef void (*fast_sentence_cbow_hs_ptr) (
    const np.uint32_t *word_point, const np.uint8_t *word_code, int codelens[MAX_SENTENCE_LEN],
    REAL_t *neu1,  REAL_t *syn0, REAL_t *syn1, const int size,
    np.uint32_t indexes[MAX_SENTENCE_LEN], const REAL_t alpha, REAL_t *work,
    int i, int j, int k) nogil

ctypedef void fast_sentence_cbow_negs_ptr) (
    int pos, const int negative, np.uint32_t *table,
    REAL_t *neu1,  REAL_t *syn0, REAL_t *syn1neg, const int size,
    np.uint32_t indexes[MAX_SENTENCE], const REAL_t alpha, REAL_t *work,
    int i, int j, int k, np.uint32_t *random_numbers) nogil

cdef scopy_ptr scopy=<scopy_ptr>PyCObject_AsVoidPtr(fblas.scopy._cpointer)  # y = x
cdef saxpy_ptr saxpy=<saxpy_ptr>PyCObject_AsVoidPtr(fblas.saxpy._cpointer)  # y += alpha * x
cdef sdot_ptr sdot=<sdot_ptr>PyCObject_AsVoidPtr(fblas.sdot._cpointer)  # float = dot(x, y)
cdef dsdot_ptr dsdot=<dsdot_ptr>PyCObject_AsVoidPtr(fblas.sdot._cpointer)  # double = dot(x, y)
cdef snrm2_ptr snrm2=<snrm2_ptr>PyCObject_AsVoidPtr(fblas.snrm2._cpointer)  # sqrt(x^2)
cdef sscal_ptr sscal=<sscal_ptr>PyCObject_AsVoidPtr(fblas.sscal._cpointer) # x = alpha * x
cdef fast_sentence_sg_hs_ptr fast_sentence_sg_hs
cdef fast_sentence_sg_neg_ptr fast_sentence_sg_neg
cdef fast_sentence_cbow_hs_ptr fast_sentence_cbow_hs
cdef fast_sentence_cbow_neg_ptr fast_sentence_cbow_neg

DEF EXP_TABLE_SIZE = 1000
DEF MAX_EXP = 6

cdef REAL_t[EXP_TABLE_SIZE] EXP_TABLE

cdef int ONE = 1
cdef REAL_t ONEF = <REAL_t>1.0

cdef void fast_sentence0_sg_hs(
    const np.uint32_t *word_point, const np.uint8_t *word_code, const int codelen,
    REAL_t *syn0, REAL_t *syn1, const int size,
    const np.uint32_t word2_index, const REAL_t alpha, REAL_t *work) nogil:

    cdef long long a, b
    cdef long long row1 = word2_index * size, row2
    cdef REAL_t f, g

    memset(work, 0, size * cython.sizeof(REAL_t))
    for b in range(codelen):
        row2 = word_point[b] * size
        f = <REAL_t>dsdot(&size, &syn0[row1], &ONE, &syn1[row2], &ONE)
        if f <= -MAX_EXP or f >= MAX_EXP:
            continue
        f = EXP_TABLE[<int>((f + MAX_EXP) * (EXP_TABLE_SIZE / MAX_EXP / 2))]
        g = (1 - word_code[b] - f) * alpha
        saxpy(&size, &g, &syn1[row2], &ONE, work, &ONE)
        saxpy(&size, &g, &syn0[row1], &ONE, &syn1[row2], &ONE)
    saxpy(&size, &ONEF, work, &ONE, &syn0[row1], &ONE)


cdef void fast_sentence1_sg_hs(
    const np.uint32_t *word_point, const np.uint8_t *word_code, const int codelen,
    REAL_t *syn0, REAL_t *syn1, const int size,
    const np.uint32_t word2_index, const REAL_t alpha, REAL_t *work) nogil:

    cdef long long a, b
    cdef long long row1 = word2_index * size, row2
    cdef REAL_t f, g

    memset(work, 0, size * cython.sizeof(REAL_t))
    for b in range(codelen):
        row2 = word_point[b] * size
        f = <REAL_t>sdot(&size, &syn0[row1], &ONE, &syn1[row2], &ONE)
        if f <= -MAX_EXP or f >= MAX_EXP:
            continue
        f = EXP_TABLE[<int>((f + MAX_EXP) * (EXP_TABLE_SIZE / MAX_EXP / 2))]
        g = (1 - word_code[b] - f) * alpha
        saxpy(&size, &g, &syn1[row2], &ONE, work, &ONE)
        saxpy(&size, &g, &syn0[row1], &ONE, &syn1[row2], &ONE)
    saxpy(&size, &ONEF, work, &ONE, &syn0[row1], &ONE)


cdef void fast_sentence2_sg_hs(
    const np.uint32_t *word_point, const np.uint8_t *word_code, const int codelen,
    REAL_t *syn0, REAL_t *syn1, const int size,
    const np.uint32_t word2_index, const REAL_t alpha, REAL_t *work) nogil:

    cdef long long a, b
    cdef long long row1 = word2_index * size, row2
    cdef REAL_t f, g

    for a in range(size):
        work[a] = <REAL_t>0.0
    for b in range(codelen):
        row2 = word_point[b] * size
        f = <REAL_t>0.0
        for a in range(size):
            f += syn0[row1 + a] * syn1[row2 + a]
        if f <= -MAX_EXP or f >= MAX_EXP:
            continue
        f = EXP_TABLE[<int>((f + MAX_EXP) * (EXP_TABLE_SIZE / MAX_EXP / 2))]
        g = (1 - word_code[b] - f) * alpha
        for a in range(size):
            work[a] += g * syn1[row2 + a]
        for a in range(size):
            syn1[row2 + a] += g * syn0[row1 + a]
    for a in range(size):
        syn0[row1 + a] += work[a]

cdef void fast_sentence0_sg_neg(
    const int pos, const int negative, np.uint32_t *table
    REAL_t *syn0, REAL_t *syn1neg, const int size, const np.uint32_t word_index,
    const np.uint32_t word2_index, const REAL_t alpha, REAL_t *work, 
    np.uint32_t *random_numbers) nogil:

    cdef long long a
    cdef long long row1 = word2_index * size, row2
    cdef REAL_t f, g
    cdef int d, random_integer

    cdef np.int32_t target_index
    cdef REAL_t label

    memset(work, 0, size * cython.sizeof(REAL_t))

    for d in range(negative+1):

        if d == 0:
            target_index = word_index
            label = ONEF
        else:
            random_integer = random_numbers[pos + d - 1]
            target_index = table[random_integer]
            if target_index == word_index:
                continue
            label = <REAL_t>0.0

        row2 = target_index * size
        f = <REAL_t>dsdot(&size, &syn0[row1], &ONE, &syn1neg[row2], &ONE)
        if f <= -MAX_EXP or f >= MAX_EXP:
            continue
        f = EXP_TABLE[<int>((f + MAX_EXP) * (EXP_TABLE_SIZE / MAX_EXP / 2))]
        g = (label - f) * alpha
        saxpy(&size, &g, &syn1neg[row2], &ONE, work, &ONE)
        saxpy(&size, &g, &syn0[row1], &ONE, &syn1neg[row2], &ONE)

    saxpy(&size, &ONEF, work, &ONE, &syn0[row1], &ONE)

cdef void fast_sentence1_sg_neg(
    const int pos, const int negative, np.uint32_t *table,
    REAL_t *syn0, REAL_t *syn1neg, const int size, const np.uint32_t word_index,
    const np.uint32_t word2_index, const REAL_t alpha, REAL_t *work, 
    np.uint32_t *random_numbers) nogil:

    cdef long long a
    cdef long long row1 = word2_index * size, row2
    cdef REAL_t f, g
    cdef int d, random_integer

    cdef np.int32_t target_index
    cdef REAL_t label

    memset(work, 0, size * cython.sizeof(REAL_t))

    for d in range(negative+1):

        if d == 0:
            target_index = word_index
            label = ONEF
        else:
            random_integer = random_numbers[pos + d - 1]
            target_index = table[random_integer]
            if target_index == word_index:
                continue
            label = <REAL_t>0.0

        row2 = target_index * size
        f = <REAL_t>sdot(&size, &syn0[row1], &ONE, &syn1neg[row2], &ONE)
        if f <= -MAX_EXP or f >= MAX_EXP:
            continue
        f = EXP_TABLE[<int>((f + MAX_EXP) * (EXP_TABLE_SIZE / MAX_EXP / 2))]
        g = (label - f) * alpha
        saxpy(&size, &g, &syn1neg[row2], &ONE, work, &ONE)
        saxpy(&size, &g, &syn0[row1], &ONE, &syn1neg[row2], &ONE)

    saxpy(&size, &ONEF, work, &ONE, &syn0[row1], &ONE)

cdef void fast_sentence2_sg_neg(
    const int pos, const int negative, np.uint32_t *table,
    REAL_t *syn0, REAL_t *syn1neg, const int size, const np.uint32_t word_index,
    const np.uint32_t word2_index, const REAL_t alpha, REAL_t *work, 
    np.uint32_t *random_numbers) nogil:

    cdef long long a
    cdef long long row1 = word2_index * size, row2
    cdef REAL_t f, g
    cdef int d, random_integer

    cdef np.int32_t target_index
    cdef REAL_t label

    for a in range(size):
        work[a] = <REAL_t>0.0

    for d in range(negative+1):

        if d == 0:
            target_index = word_index
            label = ONEF
        else:
            random_integer = random_numbers[pos + d - 1]
            target_index = table[random_integer]
            if target_index == word_index:
                continue
            label = <REAL_t>0.0

        row2 = target_index * size
        f = <REAL_t>0.0
        for a in range(size):
            f += syn0[row1 + a] * syn1neg[row2 + a]
        if f <= -MAX_EXP or f >= MAX_EXP:
            continue
        f = EXP_TABLE[<int>((f + MAX_EXP) * (EXP_TABLE_SIZE / MAX_EXP / 2))]
        g = (label - f) * alpha
        for a in range(size):
            work[a] += g * syn1neg[row2 + a]
        for a in range(size):
            syn1neg[row2 + a] += g * syn0[row1 + a]

    for a in range(size):
        syn0[row1 + a] += work[a]

cdef void fast_sentence0_cbow_hs(
    const np.uint32_t *word_point, const np.uint8_t *word_code, int codelens[MAX_SENTENCE_LEN],
    REAL_t *neu1, REAL_t *syn0, REAL_t *syn1, const int size,
    const np.uint32_t indexes[MAX_SENTENCE_LEN], const REAL_t alpha, REAL_t *work,
    int i, int j, int k) nogil:

    cdef long long a, b
    cdef long long row2
    cdef REAL_t f, g, count, inv_count
    cdef int m

    memset(neu1, 0, size * cython.sizeof(REAL_t))
    count = <REAL_t>0.0
    for m in range(j, k):
        if m == i or codelens[m] == 0:
            continue
        else:
            count += ONEF
            saxpy(&size, &ONEF, &syn0[indexes[m] * size], &ONE, neu1, &ONE)
    if count > (<REAL_t>0.5):
        inv_count = ONEF/count
        sscal(&size, &inv_count, neu1, &ONE)

    memset(work, 0, size * cython.sizeof(REAL_t))
    for b in range(codelens[i]):
        row2 = word_point[b] * size
        f = <REAL_t>dsdot(&size, neu1, &ONE, &syn1[row2], &ONE)
        if f <= -MAX_EXP or f >= MAX_EXP:
            continue
        f = EXP_TABLE[<int>((f + MAX_EXP) * (EXP_TABLE_SIZE / MAX_EXP / 2))]
        g = (1 - word_code[b] - f) * alpha
        saxpy(&size, &g, &syn1[row2], &ONE, work, &ONE)
        saxpy(&size, &g, neu1, &ONE, &syn1[row2], &ONE)

    for m in range(j, k):
        if m == i or codelens[m] == 0:
            continue
        else:
            saxpy(&size, &ONEF, work, &ONE, &syn0[indexes[m] * size], &ONE)

cdef void fast_sentence1_cbow_hs(
    const np.uint32_t *word_point, const np.uint8_t *word_code, int codelens[MAX_SENTENCE_LEN],
    REAL_t *neu1, REAL_t *syn0, REAL_t *syn1, const int size,
    const np.uint32_t indexes[MAX_SENTENCE_LEN], const REAL_t alpha, REAL_t *work,
    int i, int j, int k) nogil:

    cdef long long a, b
    cdef long long row2
    cdef REAL_t f, g, count, inv_count
    cdef int m

    memset(neu1, 0, size * cython.sizeof(REAL_t))
    count = <REAL_t>0.0
    for m in range(j, k):
        if m == i or codelens[m] == 0:
            continue
        else:
            count += ONEF
            saxpy(&size, &ONEF, &syn0[indexes[m] * size], &ONE, neu1, &ONE)
    if count > (<REAL_t>0.5):
        inv_count = ONEF/count
        sscal(&size, &inv_count , neu1, &ONE)

    memset(work, 0, size * cython.sizeof(REAL_t))
    for b in range(codelens[i]):
        row2 = word_point[b] * size
        f = <REAL_t>sdot(&size, neu1, &ONE, &syn1[row2], &ONE)
        if f <= -MAX_EXP or f >= MAX_EXP:
            continue
        f = EXP_TABLE[<int>((f + MAX_EXP) * (EXP_TABLE_SIZE / MAX_EXP / 2))]
        g = (1 - word_code[b] - f) * alpha
        saxpy(&size, &g, &syn1[row2], &ONE, work, &ONE)
        saxpy(&size, &g, neu1, &ONE, &syn1[row2], &ONE)

    for m in range(j, k):
        if m == i or codelens[m] == 0:
            continue
        else:
            saxpy(&size, &ONEF, work, &ONE, &syn0[indexes[m]*size], &ONE)

cdef void fast_sentence2_cbow_hs(
    const np.uint32_t *word_point, const np.uint8_t *word_code, int codelens[MAX_SENTENCE_LEN],
    REAL_t *neu1, REAL_t *syn0, REAL_t *syn1, const int size,
    const np.uint32_t indexes[MAX_SENTENCE_LEN], const REAL_t alpha, REAL_t *work,
    int i, int j, int k) nogil:

    cdef long long a, b
    cdef long long row2
    cdef REAL_t f, g, count
    cdef int m

    for a in range(size):
        neu1[a] = <REAL_t>0.0
    count = <REAL_t>0.0
    for m in range(j, k):
        if m == i or codelens[m] == 0:
            continue
        else:
            count += ONEF
            for a in range(size):
                neu1[a] += syn0[indexes[m] * size]
    if count > (<REAL_t>0.5):
        for a in range(size):
            neu1[a] /= count

    for a in range(size):
        work[a] = <REAL_t>0.0
    for b in range(codelens[i]):
        row2 = word_point[b] * size
        f = <REAL_t>0.0
        for a in range(size):
            f += neu1[a] * syn1[row2 + a]
        if f <= -MAX_EXP or f >= MAX_EXP:
            continue
        f = EXP_TABLE[<int>((f + MAX_EXP) * (EXP_TABLE_SIZE / MAX_EXP / 2))]
        g = (1 - word_code[b] - f) * alpha
        for a in range(size):
            work[a] += g * syn1[row2 + a]
        for a in range(size):
            syn1[row2 + a] += g * neu1[a]

    for m in range(j, k):
        if m == i or codelens[m] == 0:
            continue
        else:
            for a in range(size):
                syn0[indexes[m] * size + a] += work[a]

cdef void fast_sentence0_cbow_negs(
    int pos, const int negative, np.uint32_t *table,
    REAL_t *neu1,  REAL_t *syn0, REAL_t *syn1neg, const int size,
    np.uint32_t indexes[MAX_SENTENCE], const REAL_t alpha, REAL_t *work,
    int i, int j, int k, np.uint32_t *random_numbers) nogil:

    cdef long long a
    cdef long long row2
    cdef REAL_t f, g, count, inv_count
    cdef int m, d, random_integer

    cdef np.int32_t target_index
    cdef REAL_t label
    cdef np.int32_t word_index
    word_index = indexes[i]

    memset(neu1, 0, size * cython.sizeof(REAL_t))
    count = <REAL_t>0.0
    for m in range(j, k):
        if m == i or codelens[m] == 0:
            continue
        else:
            count += ONEF
            saxpy(&size, &ONEF, &syn0[indexes[m] * size], &ONE, neu1, &ONE)
    if count > (<REAL_t>0.5):
        inv_count = ONEF/count
        sscal(&size, &inv_count, neu1, &ONE)

    memset(work, 0, size * cython.sizeof(REAL_t))
    for d in range(negative+1):

        if d == 0:
            target_index = word_index
            label = ONEF
        else:
            random_integer = random_numbers[pos]
            target_index = table[random_integer]
            if target_index == word_index:
                continue
            label = <REAL_t>0.0
            pos += 1

        row2 = target_index * size
        f = <REAL_t>dsdot(&size, neu1, &ONE, &syn1neg[row2], &ONE)
        if f <= -MAX_EXP or f >= MAX_EXP:
            continue
        f = EXP_TABLE[<int>((f + MAX_EXP) * (EXP_TABLE_SIZE / MAX_EXP / 2))]
        g = (label - f) * alpha
        saxpy(&size, &g, &syn1neg[row2], &ONE, work, &ONE)
        saxpy(&size, &g, neu1, &ONE, &syn1neg[row2], &ONE)

    for m in range(j,k):
        if m == i or codelens[m] == 0:
            continue
        else:
            saxpy(&size, &ONEF, work, &ONE, &syn0[indexes[m]*size], &ONE)

cdef void fast_sentence1_cbow_negs(
    int pos, const int negative, np.uint32_t *table,
    REAL_t *neu1,  REAL_t *syn0, REAL_t *syn1neg, const int size,
    np.uint32_t indexes[MAX_SENTENCE], const REAL_t alpha, REAL_t *work, 
    int i, int j, int k, np.uint32_t *random_numbers) nogil:

    cdef long long a
    cdef long long row2
    cdef REAL_t f, g, count, inv_count
    cdef int m, d, random_integer

    cdef np.int32_t target_index
    cdef REAL_t label
    cdef np.int32_t word_index
    word_index = indexes[i]

    memset(neu1, 0, size * cython.sizeof(REAL_t))
    count = <REAL_t>0.0
    for m in range(j, k):
        if m == i or codelens[m] == 0:
            continue
        else:
            count += ONEF
            saxpy(&size, &ONEF, &syn0[indexes[m] * size], &ONE, neu1, &ONE)
    if count > (<REAL_t>0.5):
        inv_count = ONEF/count
        sscal(&size, &inv_count, neu1, &ONE)

    memset(work, 0, size * cython.sizeof(REAL_t))
    for d in range(negative+1):

        if d == 0:
            target_index = word_index
            label = ONEF
        else:
            random_integer = random_numbers[pos]
            target_index = table[random_integer]
            if target_index == word_index:
                continue
            label = <REAL_t>0.0
            pos += 1

        row2 = target_index * size
        f = <REAL_t>0.0
        for a in range(size):
            f += neu1[a] * syn1[row2 + a]
        if f <= -MAX_EXP or f >= MAX_EXP:
            continue
        f = EXP_TABLE[<int>((f + MAX_EXP) * (EXP_TABLE_SIZE / MAX_EXP / 2))]
        g = (label - f) * alpha
        saxpy(&size, &g, &syn1neg[row2], &ONE, work, &ONE)
        saxpy(&size, &g, neu1, &ONE, &syn1neg[row2], &ONE)

    for m in range(j,k):
        if m == i or codelens[m] == 0:
            continue
        else:
            saxpy(&size, &ONEF, work, &ONE, &syn0[indexes[m]*size], &ONE)

cdef void fast_sentence2_cbow_negs(
    int pos, const int negative, np.uint32_t *table,
    REAL_t *neu1,  REAL_t *syn0, REAL_t *syn1neg, const int size,
    np.uint32_t indexes[MAX_SENTENCE], const REAL_t alpha, REAL_t *work,
    int i, int j, int k, np.uint32_t *random_numbers) nogil:

    cdef long long a
    cdef long long row2
    cdef REAL_t f, g, count, inv_count
    cdef int m, d, random_integer

    cdef np.int32_t target_index
    cdef REAL_t label
    cdef np.int32_t word_index
    word_index = indexes[i]

    for a in range(size):
        neu1[a] = <REAL_t>0.0
    count = <REAL_t>0.0
    for m in range(j, k):
        if m == i or codelens[m] == 0:
            continue
        else:
            count += ONEF
            for a in range(size):
                neu1[a] += syn0[indexes[m] * size]
    if count > (<REAL_t>0.5):
        for a in range(size):
            neu1[a] /= count

    for a in range(size):
        work[a] = <REAL_t>0.0
    for d in range(negative+1):

        if d == 0:
            target_index = word_index
            label = ONEF
        else:
            random_integer = random_numbers[pos]
            target_index = table[random_integer]
            if target_index == word_index:
                continue
            label = <REAL_t>0.0
            pos += 1

        row2 = target_index * size
        f = <REAL_t>0.0
        for a in range(size):
            f += neu1[a] * syn1[row2 + a]
        if f <= -MAX_EXP or f >= MAX_EXP:
            continue
        f = EXP_TABLE[<int>((f + MAX_EXP) * (EXP_TABLE_SIZE / MAX_EXP / 2))]
        g = (label - f) * alpha
        for a in range(size):
            work[a] += g * syn1[row2 + a]
        for a in range(size):
            syn1[row2 + a] += g * neu1[a]

    for m in range(j, k):
        if m == i or codelens[m] == 0:
            continue
        else:
            for a in range(size):
                syn0[indexes[m] * size + a] += work[a]

def train_sentence_sg(model, sentence, alpha, _work):
    cdef int negative = model.negative

    cdef REAL_t *syn0 = <REAL_t *>(np.PyArray_DATA(model.syn0))
    cdef REAL_t *work
    cdef np.uint32_t word2_index
    cdef REAL_t _alpha = alpha
    cdef int size = model.layer1_size

    cdef int codelens[MAX_SENTENCE_LEN]
    cdef np.uint32_t indexes[MAX_SENTENCE_LEN]
    cdef np.uint32_t reduced_windows[MAX_SENTENCE_LEN]
    cdef int sentence_len
    cdef int window = model.window

    cdef int i, j, k, m, pos
    cdef long result = 0

    if negative == 0:
        cdef REAL_t *syn1 = <REAL_t *>(np.PyArray_DATA(model.syn1))
        cdef np.uint32_t *points[MAX_SENTENCE_LEN]
        cdef np.uint8_t *codes[MAX_SENTENCE_LEN]
    else:
        cdef REAL_t *syn1neg = <REAL_t *>(np.PyArray_DATA(model.syn1))
        cdef np.uint32_t *table = <np.uint32_t *>(np.PyArray_DATA(model.table))
        cdef int table_size = len(table)
        cdef np.uint32_t word_index
        cdef np.uint32_t *random_numbers = <np.uint32_t *>(np.PyArray_DATA(model.random_numbers))

    # convert Python structures to primitive types, so we can release the GIL
    work = <REAL_t *>np.PyArray_DATA(_work)
    sentence_len = <int>min(MAX_SENTENCE_LEN, len(sentence))

    for i in range(sentence_len):
        word = sentence[i]
        if word is None:
            codelens[i] = 0

    pos = 0
    for i in range (sentence_len):
	    if codelens[i] != 0:
            indexes[i] = word.index
            reduced_windows[i] = np.random.randint(window)
            if negative == 0:
                codelens[i] = <int>len(word.code)
                codes[i] = <np.uint8_t *>np.PyArray_DATA(word.code)
                points[i] = <np.uint32_t *>np.PyArray_DATA(word.point)
            else:
                j = i - window + reduced_windows[i]
                if j < 0:
                    j = 0
                k = i + window + 1 - reduced_windows[i]
                if k > sentence_len:
                    k = sentence_len
                for j in range(j,k):
                    if j == i or codelens[j] == 0:
                        continue
                    for m in range(negative):
                        random_numbers[pos] = np.random.randint(table_size)
                        pos += 1
            result += 1

    # release GIL & train on the sentence
    with nogil:
        pos = 0
        for i in range(sentence_len):
            if codelens[i] == 0:
                continue
            j = i - window + reduced_windows[i]
            if j < 0:
                j = 0
            k = i + window + 1 - reduced_windows[i]
            if k > sentence_len:
                k = sentence_len
            for j in range(j, k):
                if j == i or codelens[j] == 0:
                    continue
                if negative == 0:
                    fast_sentence_sg_hs(points[i], codes[i], codelens[i], syn0, syn1, size, indexes[j], _alpha, work)
                else:
                    fast_sentence_sg_neg(pos, negative, table, syn0, syn1neg, size, indexes[i], indexes[j],
                                        _alpha, work, random_numbers)
                    pos += negative

    return result


def train_sentence_cbow(model, sentence, alpha, _work, _neu1):
    cdef int negative = model.negative

    cdef REAL_t *syn0 = <REAL_t *>(np.PyArray_DATA(model.syn0))
    cdef REAL_t *work
    cdef REAL_t *neu1
    cdef np.uint32_t word2_index
    cdef REAL_t _alpha = alpha
    cdef int size = model.layer1_size

    cdef int codelens[MAX_SENTENCE_LEN]
    cdef np.uint32_t indexes[MAX_SENTENCE_LEN]
    cdef np.uint32_t reduced_windows[MAX_SENTENCE_LEN]
    cdef int sentence_len
    cdef int window = model.window

    cdef int i, j, k, pos
    cdef long result = 0

    if negative == 0:
        cdef REAL_t *syn1 = <REAL_t *>(np.PyArray_DATA(model.syn1))
        cdef np.uint32_t *points[MAX_SENTENCE_LEN]
        cdef np.uint8_t *codes[MAX_SENTENCE_LEN]
    else:
        cdef REAL_t *syn1neg = <REAL_t *>(np.PyArray_DATA(model.syn1))
        cdef np.uint32_t *table = <np.uint32_t *>(np.PyArray_DATA(model.table))
        cdef int table_size = len(table)
        cdef np.uint32_t *random_numbers = <np.uint32_t *>(np.PyArray_DATA(model.random_numbers))

    # convert Python structures to primitive types, so we can release the GIL
    work = <REAL_t *>np.PyArray_DATA(_work)
    sentence_len = <int>min(MAX_SENTENCE_LEN, len(sentence))
    pos = 0
    for i in range(sentence_len):
        word = sentence[i]
        if word is None:
            codelens[i] = 0
        else:
            indexes[i] = word.index
            reduced_windows[i] = np.random.randint(window)
            if negative == 0:
                codelens[i] = <int>len(word.code)
                codes[i] = <np.uint8_t *>np.PyArray_DATA(word.code)
                points[i] = <np.uint32_t *>np.PyArray_DATA(word.point)
            else:
                for m in range(negative):
                    random_numbers[pos] = np.random.randint(table_size)
                    pos += 1
            result += 1

    # release GIL & train on the sentence
    with nogil:
        pos = 0
        for i in range(sentence_len):
            if codelens[i] == 0:
                continue
            j = i - window + reduced_windows[i]
            if j < 0:
                j = 0
            k = i + window + 1 - reduced_windows[i]
            if k > sentence_len:
                k = sentence_len
            if negative == 0:
                fast_sentence_cbow(points[i], codes[i], codelens, neu1, syn0, syn1, size, indexes, _alpha, work, i, j, k)
            else:
                fast_sentence_cbow_neg(pos, negative, table, neu1, syn0, syn1neg, size, indexes, _alpha, work, i, j, k, random_numbers)
                pos += negative

    return result


def init():
    """
    Precompute function `sigmoid(x) = 1 / (1 + exp(-x))`, for x values discretized
    into table EXP_TABLE.

    """
    global fast_sentence_sg_hs
    global fast_sentence_sg_neg
    global fast_sentence_cbow_hs
    global fast_sentence_cbow_neg

    cdef int i
    cdef float *x = [<float>10.0]
    cdef float *y = [<float>0.01]
    cdef float expected = <float>0.1
    cdef int size = 1
    cdef double d_res
    cdef float *p_res

    # build the sigmoid table
    for i in range(EXP_TABLE_SIZE):
        EXP_TABLE[i] = <REAL_t>exp((i / <REAL_t>EXP_TABLE_SIZE * 2 - 1) * MAX_EXP)
        EXP_TABLE[i] = <REAL_t>(EXP_TABLE[i] / (EXP_TABLE[i] + 1))

    # check whether sdot returns double or float
    d_res = dsdot(&size, x, &ONE, y, &ONE)
    p_res = <float *>&d_res
    if (abs(d_res - expected) < 0.0001):
        fast_sentence_sg_hs = fast_sentence0_sg_hs
        fast_sentence_sg_neg = fast_sentence0_sg_neg
        fast_sentence_cbow_hs = fast_sentence0_cbow_hs
        fast_sentence_cbow_neg = fast_sentence0_cbow_neg
        return 0  # double
    elif (abs(p_res[0] - expected) < 0.0001):
        fast_sentence_sg_hs = fast_sentence1_sg_hs
        fast_sentence_sg_neg = fast_sentence1_sg_neg
        fast_sentence_cbow_hs = fast_sentence1_cbow_hs
        fast_sentence_cbow_neg = fast_sentence1_cbow_neg
        return 1  # float
    else:
        # neither => use cython loops, no BLAS
        # actually, the BLAS is so messed up we'll probably have segfaulted above and never even reach here
        fast_sentence_sg_hs = fast_sentence2_sg_hs
        fast_sentence_sg_neg = fast_sentence2_sg_neg
        fast_sentence_cbow_hs = fast_sentence2_cbow_hs
        fast_sentence_cbow_neg = fast_sentence2_cbow_neg
        return 2

FAST_VERSION = init()  # initialize the module
