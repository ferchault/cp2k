!-----------------------------------------------------------------------------!
!   CP2K: A general program to perform molecular dynamics simulations         !
!   Copyright (C) 2000 - 2015  CP2K developers group                          !
!-----------------------------------------------------------------------------!

! *****************************************************************************
!> \brief Gets a 2-d block from a dbcsr matrix
!> \param[in]  matrix DBCSR matrix
!> \param[in]  row    the row
!> \param[in]  col    the column
!> \param[out] block  the block to get (rank-2 array)
!> \param[out] tr     whether the data is transposed
!> \param[out] found  whether the block exists in the matrix
!> \param[out] row_size      (optional) logical row size of block
!> \param[out] col_size      (optional) logical column size of block
! *****************************************************************************
  SUBROUTINE dbcsr_get_2d_block_p_c(matrix,row,col,block,tr,found,&
       row_size, col_size)
    TYPE(dbcsr_obj), INTENT(INOUT)           :: matrix
    INTEGER, INTENT(IN)                      :: row, col
    COMPLEX(kind=real_4), DIMENSION(:,:), POINTER         :: block
    LOGICAL, INTENT(OUT)                     :: tr
    LOGICAL, INTENT(OUT)                     :: found
    INTEGER, INTENT(OUT), OPTIONAL           :: row_size, col_size

    CHARACTER(len=*), PARAMETER :: routineN = 'dbcsr_get_2d_block_p_c', &
      routineP = moduleN//':'//routineN

    COMPLEX(kind=real_4), DIMENSION(:), POINTER           :: block_1d
    INTEGER                                  :: rsize, csize,&
                                                blk, nze, offset,&
                                                stored_row,&
                                                stored_col, iw, nwms
    INTEGER                                  :: error_handle
    TYPE(btree_2d_data_c)          :: data_block
    LOGICAL                                  :: stored_tr
    COMPLEX(kind=real_4), DIMENSION(1,1), TARGET, SAVE    :: block0
!   ---------------------------------------------------------------------------
    IF (careful_mod) CALL timeset (routineN, error_handle)
    IF (debug_mod) THEN
       CALL dbcsr_assert (matrix%m%data_type, "EQ", dbcsr_type_complex_4,&
            dbcsr_fatal_level, dbcsr_caller_error,&
            routineN, "Data type mismatch for requested block.",__LINE__)
    ENDIF

    CALL dbcsr_get_block_index (matrix, row, col, stored_row, stored_col,&
         stored_tr, found, blk, offset)
    tr = stored_tr

    rsize = dbcsr_blk_row_size (matrix%m, stored_row)
    csize = dbcsr_blk_column_size (matrix%m, stored_col)
    IF (PRESENT (row_size)) row_size = rsize
    IF (PRESENT (col_size)) col_size = csize

    NULLIFY (block)
    IF(found) THEN
       nze = rsize*csize
       IF(nze.eq.0) THEN
          found = .TRUE.
          block => block0(1:0, 1:0)
       ELSE
          block_1d => pointer_view (dbcsr_get_data_p (&
               matrix%m%data_area, CMPLX(0.0, 0.0, real_4)), offset, offset+nze-1)
          CALL dbcsr_set_block_pointer (matrix, block, rsize, csize, offset)
       ENDIF
    ELSEIF (ASSOCIATED (matrix%m%wms)) THEN
       nwms = SIZE(matrix%m%wms)
       iw = 1
!$     CALL dbcsr_assert (nwms, "GE", omp_get_num_threads(),&
!$        dbcsr_fatal_level, dbcsr_internal_error,&
!$        routineN, "Number of work matrices not equal to number of threads", __LINE__)
!$     iw = omp_get_thread_num () + 1
       CALL dbcsr_assert (dbcsr_use_mutable (matrix%m), dbcsr_failure_level,&
            dbcsr_caller_error, routineN,&
            "Can not retrieve blocks from non-mutable work matrices.",__LINE__)
       IF (dbcsr_use_mutable (matrix%m)) THEN
          IF (.NOT. dbcsr_mutable_instantiated(matrix%m%wms(iw)%mutable)) THEN
             CALL dbcsr_mutable_new(matrix%m%wms(iw)%mutable,&
                  dbcsr_get_data_type(matrix))
          ENDIF
          CALL btree_get_c (&
               matrix%m%wms(iw)%mutable%m%btree_c,&
               make_coordinate_tuple(stored_row, stored_col),&
               data_block, found)
          IF (found) THEN
             block => data_block%p
          ENDIF
       ENDIF
    ENDIF
    IF (careful_mod) CALL timestop (error_handle)
  END SUBROUTINE dbcsr_get_2d_block_p_c


! *****************************************************************************
!> \brief Gets a 1-d block from a dbcsr matrix
!> \param[in]  matrix DBCSR matrix
!> \param[in]  row    the row
!> \param[in]  col    the column
!> \param[out] block  the block to get (rank-1 array)
!> \param[out] tr     whether the data is transposed
!> \param[out] found  whether the block exists in the matrix
!> \param[out] row_size      (optional) logical row size of block
!> \param[out] col_size      (optional) logical column size of block
! *****************************************************************************
  SUBROUTINE dbcsr_get_block_p_c(matrix,row,col,block,tr,found,&
       row_size, col_size)
    TYPE(dbcsr_obj), INTENT(IN)              :: matrix
    INTEGER, INTENT(IN)                      :: row, col
    COMPLEX(kind=real_4), DIMENSION(:), POINTER           :: block
    LOGICAL, INTENT(OUT)                     :: tr
    LOGICAL, INTENT(OUT)                     :: found
    INTEGER, INTENT(OUT), OPTIONAL           :: row_size, col_size

    CHARACTER(len=*), PARAMETER :: routineN = 'dbcsr_get_block_p_c', &
      routineP = moduleN//':'//routineN

    INTEGER                                  :: blk, csize, &
                                                nze, offset, &
                                                rsize, stored_row,&
                                                stored_col
    LOGICAL                                  :: stored_tr

!   ---------------------------------------------------------------------------

    IF (debug_mod) THEN
       CALL dbcsr_assert (matrix%m%data_type, "EQ", dbcsr_type_complex_4,&
            dbcsr_fatal_level, dbcsr_caller_error,&
            routineN, "Data type mismatch for requested block.",__LINE__)
    ENDIF

    CALL dbcsr_get_block_index (matrix, row, col, stored_row, stored_col,&
         stored_tr, found, blk, offset)
    tr = stored_tr

    rsize = dbcsr_blk_row_size (matrix%m, stored_row)
    csize = dbcsr_blk_column_size (matrix%m, stored_col)
    IF (PRESENT (row_size)) row_size = rsize
    IF (PRESENT (col_size)) col_size = csize

    NULLIFY (block)
    IF(found) THEN
       nze = rsize*csize
       !
       block => pointer_view (&
            dbcsr_get_data_p (matrix%m%data_area, CMPLX(0.0, 0.0, real_4)), offset, offset+nze-1&
            )
    ELSEIF (ASSOCIATED (matrix%m%wms)) THEN
       CALL dbcsr_assert (dbcsr_use_mutable (matrix%m), dbcsr_failure_level,&
            dbcsr_caller_error, routineN,&
            "Can not retrieve blocks from non-mutable work matrices.",__LINE__)
       CALL dbcsr_assert ("NOT", dbcsr_use_mutable (matrix%m), dbcsr_failure_level,&
            dbcsr_caller_error, routineN,&
            "Can not retrieve rank-1 block pointers from mutable work matrices.",__LINE__)
    ENDIF
  END SUBROUTINE dbcsr_get_block_p_c


! *****************************************************************************
!> \brief Put a 2-D block in a DBCSR matrix using the btree
!> \param[in.out] matrix      DBCSR matrix
!> \param[in]  row            the row
!> \param[in]  col            the column
!> \param[in]  block          the block to reserve; added if not NULL
!> \param[in] transposed      the block holds transposed data
!> \param[out] existed        (optional) block already existed
! *****************************************************************************
  SUBROUTINE dbcsr_reserve_block2d_c(matrix, row, col, block,&
       transposed, existed)
    TYPE(dbcsr_obj), INTENT(INOUT)           :: matrix
    INTEGER, INTENT(IN)                      :: row, col
    COMPLEX(kind=real_4), DIMENSION(:,:), POINTER         :: block
    LOGICAL, INTENT(IN), OPTIONAL            :: transposed
    LOGICAL, INTENT(OUT), OPTIONAL           :: existed

    CHARACTER(len=*), PARAMETER :: routineN = 'dbcsr_reserve_block2d_c', &
      routineP = moduleN//':'//routineN

    TYPE(btree_2d_data_c)          :: data_block, data_block2
    INTEGER                                  :: col_size, row_size, &
                                                stored_row, stored_col, &
                                                iw, nwms
    INTEGER, DIMENSION(:), POINTER           :: col_blk_size, row_blk_size
    LOGICAL                                  :: found, gift, tr, sym_tr
    COMPLEX(kind=real_4), DIMENSION(:,:), POINTER         :: original_block

!   ---------------------------------------------------------------------------

    gift = ASSOCIATED (block)
    IF (gift) THEN
       original_block => block
    ELSE
       NULLIFY (original_block)
    ENDIF
    row_blk_size => array_data (matrix%m%row_blk_size)
    col_blk_size => array_data (matrix%m%col_blk_size)
    row_size = row_blk_size(row)
    col_size = col_blk_size(col)

    stored_row = row ; stored_col = col
    IF (PRESENT (transposed)) THEN
       tr = transposed
    ELSE
       tr = .FALSE.
    ENDIF
    sym_tr = .FALSE.
    CALL dbcsr_get_stored_coordinates (matrix, stored_row, stored_col)
    IF (.NOT.ASSOCIATED (matrix%m%wms)) THEN
       CALL dbcsr_work_create (matrix, work_mutable=.TRUE.)
       !$OMP MASTER
       matrix%m%valid = .FALSE.
       !$OMP END MASTER
       !$OMP BARRIER
    ENDIF

    NULLIFY (data_block%p)
    IF (.NOT. gift) THEN
       ALLOCATE (data_block%p (row_size, col_size))
       block => data_block%p
    ELSE
       data_block%p => block
    ENDIF
    data_block%tr = tr

    nwms = SIZE(matrix%m%wms)
    iw = 1
!$  CALL dbcsr_assert (nwms, "GE", omp_get_num_threads(),&
!$     dbcsr_fatal_level, dbcsr_internal_error,&
!$     routineN, "Number of work matrices not equal to number of threads", &
!$     __LINE__)
!$  iw = omp_get_thread_num () + 1
    CALL btree_add_c (matrix%m%wms(iw)%mutable%m%btree_c,&
         make_coordinate_tuple(stored_row, stored_col),&
         data_block, found, data_block2)

    IF (.NOT. found) THEN
!$OMP CRITICAL (critical_reserve_block2d)
       matrix%m%valid = .FALSE.
!$OMP END CRITICAL (critical_reserve_block2d)
       matrix%m%wms(iw)%lastblk = matrix%m%wms(iw)%lastblk + 1
       matrix%m%wms(iw)%datasize = matrix%m%wms(iw)%datasize + row_size*col_size
    ELSE
       IF (.NOT. gift) THEN
          DEALLOCATE (data_block%p)
       ELSE
          DEALLOCATE (original_block)
       ENDIF
       block => data_block2%p
    ENDIF
    IF (PRESENT (existed)) existed = found
  END SUBROUTINE dbcsr_reserve_block2d_c

! *****************************************************************************
!> \brief Put a 2-D block in a DBCSR matrix
!> \param[in.out] matrix      DBCSR matrix
!> \param[in]  row            the row
!> \param[in]  col            the column
!> \param[in]  block          the block to put
!> \param[in]  transposed     the block is transposed
!> \param[in]  summation      (optional) if block exists, then sum the new
!>                            block to the old one instead of replacing it
!> \param[in]  scale          (optional) scale the block being added
! *****************************************************************************
  SUBROUTINE dbcsr_put_block2d_c(matrix, row, col, block, transposed,&
       summation, scale)
    TYPE(dbcsr_obj), INTENT(INOUT)           :: matrix
    INTEGER, INTENT(IN)                      :: row, col
    COMPLEX(kind=real_4), DIMENSION(:,:), INTENT(IN)      :: block
    LOGICAL, INTENT(IN), OPTIONAL            :: transposed, summation
    COMPLEX(kind=real_4), INTENT(IN), OPTIONAL            :: scale

    CHARACTER(len=*), PARAMETER :: routineN = 'dbcsr_put_block2d_c', &
      routineP = moduleN//':'//routineN

    LOGICAL                                  :: tr, do_sum

    IF (PRESENT (transposed)) THEN
       tr = transposed
    ELSE
       tr = .FALSE.
    ENDIF
    IF (PRESENT (summation)) THEN
       do_sum = summation
    ELSE
       do_sum = .FALSE.
    ENDIF
    IF (PRESENT (scale)) THEN
       CALL dbcsr_put_block (matrix, row, col,&
            RESHAPE (block, (/SIZE(block)/)), tr, do_sum, scale)
    ELSE
       CALL dbcsr_put_block (matrix, row, col,&
            RESHAPE (block, (/SIZE(block)/)), tr, do_sum)
    ENDIF
  END SUBROUTINE dbcsr_put_block2d_c

! *****************************************************************************
!> \brief Inserts a block in a dbcsr matrix.
!>
!> If the block exists, the current data is overwritten.
!> \param[in]  matrix         DBCSR matrix
!> \param[in]  row            the logical row
!> \param[in]  col            the logical column
!> \param[in]  block          the block to put
!> \param[in]  transposed     (optional) the block is transposed
!> \param[in]  summation      (optional) if block exists, then sum the new
!>                            block to the old one instead of replacing it
!> \param[in]  scale          (optional) scale the block being added
! *****************************************************************************
  SUBROUTINE dbcsr_put_block_c(matrix, row, col, block, transposed,&
       summation, scale)
    TYPE(dbcsr_obj), INTENT(INOUT)           :: matrix
    INTEGER, INTENT(IN)                      :: row, col
    COMPLEX(kind=real_4), DIMENSION(:), INTENT(IN)        :: block
    LOGICAL, INTENT(IN), OPTIONAL            :: transposed, summation
    COMPLEX(kind=real_4), INTENT(IN), OPTIONAL            :: scale

    CHARACTER(len=*), PARAMETER :: routineN = 'dbcsr_put_block_c', &
      routineP = moduleN//':'//routineN

    TYPE(btree_2d_data_c)          :: data_block, data_block2
    INTEGER                                  :: blk, col_size, &
                                                nze, offset, &
                                                row_size, blk_p,&
                                                stored_row, stored_col,&
                                                iw, nwms
    LOGICAL                                  :: found, tr, do_sum, tr_diff,&
                                                sym_tr
    COMPLEX(kind=real_4), DIMENSION(:), POINTER           :: block_1d

!   ---------------------------------------------------------------------------
    IF (PRESENT (transposed)) THEN
       tr = transposed
    ELSE
       tr = .FALSE.
    ENDIF
    IF (PRESENT (summation)) THEN
       do_sum = summation
    ELSE
       do_sum = .FALSE.
    ENDIF
    row_size = dbcsr_blk_row_size(matrix, row)
    col_size = dbcsr_blk_column_size(matrix, col)
    IF (tr) CALL swap (row_size, col_size)

    stored_row = row ; stored_col = col; sym_tr = .FALSE.
    CALL dbcsr_get_stored_coordinates (matrix%m, stored_row, stored_col)
    nze = row_size*col_size
    !
    IF (debug_mod) THEN
       CALL dbcsr_assert (SIZE(block), "GE", nze, dbcsr_fatal_level,&
            dbcsr_caller_error, routineN, "Invalid block dimensions",__LINE__)
    ENDIF
    CALL dbcsr_get_stored_block_info (matrix%m, stored_row, stored_col,&
         found, blk, offset)
    IF(found) THEN
       ! let's copy the block
       offset = ABS (offset)
       ! Fix the index if the new block's transpose flag is different
       ! from the old one.
       tr_diff = .FALSE.
       IF (matrix%m%blk_p(blk).LT.0 .NEQV. tr) THEN
          tr_diff = .TRUE.
          matrix%m%blk_p(blk) = -matrix%m%blk_p(blk)
       ENDIF
       block_1d => pointer_view (dbcsr_get_data_p (&
            matrix%m%data_area, CMPLX(0.0, 0.0, real_4)), offset, offset+nze-1)
       IF (nze .GT. 0) THEN
          IF (do_sum) THEN
             IF(tr_diff) &
                  block_1d = RESHAPE(TRANSPOSE(RESHAPE(block_1d,(/col_size,row_size/))),(/nze/))
             IF (PRESENT (scale)) THEN
                CALL caxpy (nze, scale, block(1:nze), 1,&
                     block_1d, 1)
             ELSE
                CALL caxpy (nze, CMPLX(1.0, 0.0, real_4), block(1:nze), 1,&
                     block_1d, 1)
             ENDIF
          ELSE
             IF (PRESENT (scale)) THEN
                CALL ccopy (nze, scale*block(1:nze), 1,&
                     block_1d, 1)
             ELSE
                CALL ccopy (nze, block(1:nze), 1,&
                     block_1d, 1)
             ENDIF
          ENDIF
       ENDIF
    ELSE
       !!@@@
       !call cp_assert (associated (matrix%m%wms), cp_fatal_level,&
       !     cp_caller_error, routineN, "Work matrices not prepared")
       IF (.NOT.ASSOCIATED (matrix%m%wms)) THEN
          CALL dbcsr_work_create (matrix, nblks_guess=1,&
               sizedata_guess=SIZE(block))
       ENDIF
       nwms = SIZE(matrix%m%wms)
       iw = 1
!$     IF (debug_mod) THEN
!$     CALL dbcsr_assert (nwms, "GE", omp_get_num_threads(),&
!$        dbcsr_fatal_level, dbcsr_internal_error,&
!$        routineN, "Number of work matrices not equal to number of threads", __LINE__)
!$     ENDIF
!$     iw = omp_get_thread_num () + 1
       blk_p = matrix%m%wms(iw)%datasize + 1
       IF (.NOT.dbcsr_wm_use_mutable (matrix%m%wms(iw))) THEN
          IF (tr) blk_p = -blk_p
          CALL add_work_coordinate (matrix%m%wms(iw), row, col, blk_p)
          CALL dbcsr_data_ensure_size (matrix%m%wms(iw)%data_area,&
               matrix%m%wms(iw)%datasize+SIZE(block),&
               factor=default_resize_factor)
          IF (PRESENT (scale)) THEN
             CALL dbcsr_data_set (matrix%m%wms(iw)%data_area, ABS(blk_p),&
                  data_size=SIZE(block), src=scale*block, source_lb=1)
          ELSE
             CALL dbcsr_data_set (matrix%m%wms(iw)%data_area, ABS(blk_p),&
                  data_size=SIZE(block), src=block, source_lb=1)
          ENDIF
       ELSE
          ALLOCATE (data_block%p (row_size, col_size))
          IF (PRESENT (scale)) THEN
             data_block%p(:,:) = scale*RESHAPE (block, (/row_size, col_size/))
          ELSE
             data_block%p(:,:) = RESHAPE (block, (/row_size, col_size/))
          ENDIF
          data_block%tr = tr
          IF (.NOT. dbcsr_mutable_instantiated(matrix%m%wms(iw)%mutable)) THEN
             CALL dbcsr_mutable_new(matrix%m%wms(iw)%mutable,&
                  dbcsr_get_data_type(matrix))
          ENDIF
          IF (.NOT. do_sum) THEN
             CALL btree_add_c (&
                  matrix%m%wms(iw)%mutable%m%btree_c,&
                  make_coordinate_tuple(stored_row, stored_col),&
                  data_block, found, data_block2, replace=.TRUE.)
             IF (found) THEN
                CALL dbcsr_assert (ASSOCIATED (data_block2%p), dbcsr_warning_level,&
                     dbcsr_internal_error, routineN,&
                     "Data was not present in block",__LINE__)
                IF (ASSOCIATED (data_block2%p)) DEALLOCATE (data_block2%p)
             ENDIF
          ELSE
             CALL btree_add_c (&
                  matrix%m%wms(iw)%mutable%m%btree_c,&
                  make_coordinate_tuple(stored_row, stored_col),&
                  data_block, found, data_block2, replace=.FALSE.)
             IF (found) THEN
                IF(nze > 0) &
                   CALL caxpy (nze, CMPLX(1.0, 0.0, real_4), block(1), 1,&
                        data_block2%p(1,1), 1)
                CALL dbcsr_assert (ASSOCIATED (data_block%p), dbcsr_warning_level,&
                     dbcsr_internal_error, routineN,&
                     "Data was not present in block",__LINE__)
                IF (ASSOCIATED (data_block%p)) DEALLOCATE (data_block%p)
             ENDIF
          ENDIF
          IF (.NOT. found) THEN
             matrix%m%wms(iw)%lastblk = matrix%m%wms(iw)%lastblk + 1
          ENDIF
       ENDIF
       IF (.NOT. found) THEN
          matrix%m%wms(iw)%datasize = matrix%m%wms(iw)%datasize + SIZE (block)
       ELSE
       ENDIF
!$OMP CRITICAL (dbcsr_put_block_critical)
       matrix%m%valid = .FALSE.
!$OMP END CRITICAL (dbcsr_put_block_critical)
    ENDIF
  END SUBROUTINE dbcsr_put_block_c


! *****************************************************************************
!> \brief Sets a pointer, possibly using the buffers.
!> \param[in] matrix           Matrix to use
!> \param pointer_any The pointer to set
!> \param rsize Row size of block to point to
!> \param csize Column size of block to point to
!> \param[in] base_offset      The block pointer
! *****************************************************************************
  SUBROUTINE dbcsr_set_block_pointer_2d_c (&
       matrix, pointer_any, rsize, csize, base_offset)
    TYPE(dbcsr_obj), INTENT(IN)              :: matrix
    COMPLEX(kind=real_4), DIMENSION(:,:), POINTER         :: pointer_any
    INTEGER, INTENT(IN)                      :: rsize, csize
    INTEGER, INTENT(IN)                      :: base_offset

    CHARACTER(len=*), PARAMETER :: &
      routineN = 'dbcsr_set_block_pointer_2d_c', &
      routineP = moduleN//':'//routineN

    INTEGER                                  :: error_handler
    COMPLEX(kind=real_4), DIMENSION(:), POINTER           :: lin_blk_p

!   ---------------------------------------------------------------------------

    IF (careful_mod) CALL timeset (routineN, error_handler)
    CALL dbcsr_get_data (matrix%m%data_area, lin_blk_p,&
         lb=base_offset, ub=base_offset+rsize*csize-1)
    CALL pointer_rank_remap2 (pointer_any, rsize, csize,&
         lin_blk_p)
    IF (careful_mod) CALL timestop (error_handler)
  END SUBROUTINE dbcsr_set_block_pointer_2d_c
