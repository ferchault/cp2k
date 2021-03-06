!-----------------------------------------------------------------------------!
!   CP2K: A general program to perform molecular dynamics simulations         !
!   Copyright (C) 2000 - 2015  CP2K developers group                          !
!-----------------------------------------------------------------------------!

! *****************************************************************************
!> \brief Processes MM stack and issues BLAS xGEMM calls
!>
!> \param[in] params           Stack of MM parameters
!> \param[in] stack_size       Number of parameters
!> \param[in] a_data           Left-matrix data
!> \param[in] b_data           Right-matrix data
!> \param[in,out] c_data       Product data
! *****************************************************************************
  SUBROUTINE blas_process_mm_stack_d(params,&
       stack_size,&
       a_data, b_data, c_data)
    INTEGER, INTENT(IN)                       :: stack_size
    INTEGER, DIMENSION(dbcsr_ps_width,1:stack_size), &
      INTENT(IN)                              :: params
    REAL(kind=real_8), DIMENSION(*), INTENT(IN)         :: a_data, &
                                                 b_data
    REAL(kind=real_8), DIMENSION(*), INTENT(INOUT)      :: c_data

    CHARACTER(len=*), PARAMETER :: routineN = 'blas_process_mm_stack_d', &
      routineP = moduleN//':'//routineN

    INTEGER                                   :: sp

!   ---------------------------------------------------------------------------

    DO sp = 1, stack_size
       CALL DGEMM('N',&
            'N',&
            params(p_m,sp), params(p_n,sp),& !m, n
            params(p_k,sp),& ! k
            1.0_real_8,& ! alpha
            a_data(params(p_a_first,sp)),& ! A
            params(p_m,sp),& !lda
            b_data(params(p_b_first,sp)),& ! B
            params(p_k,sp),& !ldb
            1.0_real_8,& ! beta
            c_data(params(p_c_first,sp)), params(p_m,sp))
    ENDDO
  END SUBROUTINE blas_process_mm_stack_d

! *****************************************************************************
!> \brief Processes MM stack and issues internal MM calls.
!>
!> \param[in] params           Stack of MM parameters
!> \param[in] stack_size       Number of parameters
!> \param[in] a_data           Left-matrix data
!> \param[in] b_data           Right-matrix data
!> \param[in,out] c_data       Product data
! *****************************************************************************
  SUBROUTINE internal_process_mm_stack_d(params, stack_size,&
       a_data, b_data, c_data)
    INTEGER, INTENT(IN)                       :: stack_size
    INTEGER, DIMENSION(dbcsr_ps_width,1:stack_size), &
      INTENT(IN)                              :: params
    REAL(kind=real_8), DIMENSION(*), INTENT(IN)         :: a_data, &
                                                 b_data
    REAL(kind=real_8), DIMENSION(*), INTENT(INOUT)      :: c_data

    CHARACTER(len=*), PARAMETER :: routineN = 'internal_process_mm_stack_d', &
      routineP = moduleN//':'//routineN

    INTEGER                                   :: sp

!   ---------------------------------------------------------------------------

    DO sp = 1, stack_size
       CALL internal_mm_d_nn(&
            params(p_m,sp),&
            params(p_n,sp),&
            params(p_k,sp),&
            a_data(params(p_a_first,sp)),&
            b_data(params(p_b_first,sp)),&
            c_data(params(p_c_first,sp)))
    ENDDO
  END SUBROUTINE internal_process_mm_stack_d


! *****************************************************************************
!> \brief Processes MM stack and issues SMM library calls
!>
!> \param stack_descr ...
!> \param[in] params           Stack of MM parameters
!> \param[in] stack_size       Number of parameters
!> \param[in] a_data           Left-matrix data
!> \param[in] b_data           Right-matrix data
!> \param[in,out] c_data       Product data
! *****************************************************************************
  SUBROUTINE smm_process_mm_stack_d(stack_descr, params,&
       stack_size,&
       a_data, b_data, c_data)
    INTEGER, INTENT(IN)                       :: stack_size
    TYPE(stack_descriptor_type), INTENT(IN)   :: stack_descr
    INTEGER, DIMENSION(dbcsr_ps_width,1:stack_size), &
      INTENT(IN)                              :: params
    REAL(kind=real_8), DIMENSION(*), INTENT(IN)         :: a_data, &
                                                 b_data
    REAL(kind=real_8), DIMENSION(*), INTENT(INOUT)      :: c_data

    CHARACTER(len=*), PARAMETER :: routineN = 'smm_process_mm_stack_d', &
      routineP = moduleN//':'//routineN

    INTEGER                                   :: sp

!   ---------------------------------------------------------------------------
#if defined(__HAS_smm_vec) && defined(__HAS_smm_dnn)

    IF(stack_descr%defined_mnk) THEN
       CALL smm_vec_dnn (stack_descr%m, stack_descr%n, stack_descr%k, &
         a_data, b_data, c_data, stack_size, &
         dbcsr_ps_width, params, p_a_first, p_b_first, p_c_first)
       RETURN
    ENDIF

#endif
    MARK_USED(stack_descr)
    DO sp = 1, stack_size
       CALL smm_dnn(&
            params(p_m,sp),&
            params(p_n,sp),&
            params(p_k,sp),&
            a_data(params(p_a_first,sp)),&
            b_data(params(p_b_first,sp)),&
            c_data(params(p_c_first,sp)))
    ENDDO

  END SUBROUTINE smm_process_mm_stack_d


! *****************************************************************************
!> \brief ...
!> \param M ...
!> \param N ...
!> \param K ...
!> \param A ...
!> \param B ...
!> \param C ...
! *****************************************************************************
  PURE SUBROUTINE internal_mm_d_nn(&
       M,N,K,A,B,C)
    INTEGER, INTENT(IN)                      :: M, N, K
    REAL(kind=real_8), INTENT(INOUT)                   :: C(M,N)
    REAL(kind=real_8), INTENT(IN)                      :: B(K,N)
    REAL(kind=real_8), INTENT(IN)                      :: A(M,K)
    C(:,:) = C(:,:) + MATMUL (A, B)
  END SUBROUTINE internal_mm_d_nn
