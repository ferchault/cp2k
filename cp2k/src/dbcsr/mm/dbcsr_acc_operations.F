!-----------------------------------------------------------------------------!
!   CP2K: A general program to perform molecular dynamics simulations         !
!   Copyright (C) 2000 - 2015  CP2K developers group                          !
!-----------------------------------------------------------------------------!

! *****************************************************************************
!> \brief   Accelerator support for DBCSR
!> \author  Urban Borstnik
!> \date    2011-04-06
!> \version 1.0
!>
!> <b>Modification history:</b>
!> - Created 2011-04-06
!> - 2014-04, Ole Schuett: generalized into acc-framework
! *****************************************************************************
MODULE dbcsr_acc_operations
  USE ISO_C_BINDING,                   ONLY: C_INT,&
                                             C_PTR
  USE acc_devmem,                      ONLY: acc_devmem_cptr,&
                                             acc_devmem_type
  USE acc_stream,                      ONLY: acc_stream_cptr,&
                                             acc_stream_type
  USE dbcsr_error_handling,            ONLY: dbcsr_abort
  USE dbcsr_mm_types,                  ONLY: dbcsr_ps_width
#include "../../base/base_uses.f90"

  IMPLICIT NONE

  PRIVATE

  CHARACTER(len=*), PARAMETER, PRIVATE :: moduleN = 'dbcsr_acc_operations'

  LOGICAL, PARAMETER :: careful_mod = .FALSE.


  PUBLIC :: dbcsr_acc_do_mm_stack, dbcsr_acc_transpose


#if defined (__DBCSR_ACC)
  INTERFACE
     FUNCTION libsmm_acc_process_cu(param_stack, stack_size, nparams,&
          data_type,&
          a_data, b_data, c_data, m_max, n_max, k_max, def_mnk,&
          stream_ptr)&
          RESULT (istat) &
          BIND(C, name="libsmm_acc_process")
    IMPORT
    TYPE(C_PTR), INTENT(IN), VALUE           :: param_stack
    INTEGER(KIND=C_INT), INTENT(IN), VALUE   :: stack_size, nparams, data_type
    TYPE(C_PTR), INTENT(IN), VALUE           :: a_data, b_data, c_data
    INTEGER(KIND=C_INT), INTENT(IN), VALUE   :: m_max, n_max, k_max, def_mnk
    TYPE(C_PTR), VALUE                       :: stream_ptr
    INTEGER(KIND=C_INT)                      :: istat

     END FUNCTION libsmm_acc_process_cu
  END INTERFACE
  
  INTERFACE
     FUNCTION libsmm_acc_transpose_cu(trs_stack, offset, nblks, buffer, data_type, m, n, stream_ptr)&
          RESULT (istat) &
          BIND(C, name="libsmm_acc_transpose")
    IMPORT
    TYPE(C_PTR), INTENT(IN), VALUE           :: trs_stack
    INTEGER(KIND=C_INT), INTENT(IN), VALUE   :: offset, nblks
    TYPE(C_PTR), INTENT(IN), VALUE           :: buffer
    INTEGER(KIND=C_INT), INTENT(IN), VALUE   :: data_type, m, n
    TYPE(C_PTR), VALUE                       :: stream_ptr
    INTEGER(KIND=C_INT)                      :: istat

     END FUNCTION libsmm_acc_transpose_cu
  END INTERFACE
#endif

CONTAINS

! *****************************************************************************
!> \brief Launch an accelerated kernel for processing a stack.
!> \param param_stack ...
!> \param stack_size ...
!> \param datatype ...
!> \param a_data ...
!> \param b_data ...
!> \param c_data ...
!> \param m_max ...
!> \param n_max ...
!> \param k_max ...
!> \param def_mnk ...
!> \param stream ...
!> \param success ...
! *****************************************************************************
  SUBROUTINE dbcsr_acc_do_mm_stack(param_stack, stack_size, datatype, &
       a_data, b_data, c_data, m_max, n_max, k_max, def_mnk, stream, success)
    TYPE(acc_devmem_type), INTENT(IN)        :: param_stack
    INTEGER, INTENT(IN)                      :: stack_size
    INTEGER, INTENT(IN)                      :: datatype
    TYPE(acc_devmem_type), INTENT(IN)        :: a_data, b_data
    TYPE(acc_devmem_type), &
      INTENT(INOUT)                          :: c_data
    INTEGER, INTENT(IN)                      :: m_max, n_max, k_max
    LOGICAL, INTENT(IN)                      :: def_mnk
    TYPE(acc_stream_type), INTENT(IN)        :: stream
    LOGICAL, INTENT(INOUT)                   :: success

#if ! defined (__DBCSR_ACC)
    MARK_USED(param_stack)
    MARK_USED(stack_size)
    MARK_USED(datatype)
    MARK_USED(a_data)
    MARK_USED(b_data)
    MARK_USED(c_data)
    MARK_USED(m_max)
    MARK_USED(n_max)
    MARK_USED(k_max)
    MARK_USED(def_mnk)
    MARK_USED(stream)
    MARK_USED(success)
    CPABORT("__DBCSR_ACC not compiled in.")
#else

    CHARACTER(len=*), PARAMETER :: routineN = 'dbcsr_acc_do_mm_stack', &
      routineP = moduleN//':'//routineN

    INTEGER                                  :: error_handle, istat
    INTEGER(KIND=C_INT)                      :: mnk

   IF (careful_mod) CALL timeset (routineN, error_handle)

    mnk = 0
    IF (def_mnk) mnk = 1

    istat = libsmm_acc_process_cu(acc_devmem_cptr(param_stack),&
                             INT(stack_size, KIND=C_INT),&
                             INT(dbcsr_ps_width, KIND=C_INT),&
                             INT(datatype, KIND=C_INT),&
                             acc_devmem_cptr(a_data),&
                             acc_devmem_cptr(b_data),&
                             acc_devmem_cptr(c_data),&
                             INT(m_max,KIND=C_INT),&
                             INT(n_max,KIND=C_INT),&
                             INT(k_max,KIND=C_INT),&
                             mnk, acc_stream_cptr(stream))

    IF (istat == 100) CALL dbcsr_abort(routineP,__LINE__,"failed due to accGetLastError().")

    success = (istat == 0) ! false if no suitable kernel was found

    IF (careful_mod) CALL timestop (error_handle)
#endif
  END SUBROUTINE dbcsr_acc_do_mm_stack


! *****************************************************************************
!> \brief Launch an accelerated transpose kernel
!> \param trs_stack ...
!> \param offset ...
!> \param nblks ...
!> \param datatype ...
!> \param buffer ...
!> \param m ...
!> \param n ...
!> \param stream ...
!> \author Ole Schuett
! *****************************************************************************
  SUBROUTINE dbcsr_acc_transpose(trs_stack, offset, nblks, datatype, buffer, m, n, stream)
    TYPE(acc_devmem_type), INTENT(IN)        :: trs_stack
    INTEGER, INTENT(IN)                      :: offset
    INTEGER, INTENT(IN)                      :: nblks
    INTEGER, INTENT(IN)                      :: datatype
    TYPE(acc_devmem_type), INTENT(IN)        :: buffer
    INTEGER, INTENT(IN)                      :: m, n
    TYPE(acc_stream_type), INTENT(IN)        :: stream

#if ! defined (__DBCSR_ACC)
    MARK_USED(trs_stack)
    MARK_USED(offset)
    MARK_USED(nblks)
    MARK_USED(datatype)
    MARK_USED(buffer)
    MARK_USED(m)
    MARK_USED(n)
    MARK_USED(stream)
    CPABORT("__DBCSR_ACC not compiled in.")
#else

    CHARACTER(len=*), PARAMETER :: routineN = 'dbcsr_acc_transpose', &
      routineP = moduleN//':'//routineN

    INTEGER                                  :: error_handle, istat

    IF (careful_mod) CALL timeset (routineN, error_handle)

    istat = libsmm_acc_transpose_cu(acc_devmem_cptr(trs_stack),&
                             INT(offset, KIND=C_INT),&
                             INT(nblks, KIND=C_INT),&
                             acc_devmem_cptr(buffer),&
                             INT(datatype, KIND=C_INT),&
                             INT(m,KIND=C_INT),&
                             INT(n,KIND=C_INT),&
                             acc_stream_cptr(stream))

    IF (istat /= 0) CALL dbcsr_abort(routineP,__LINE__,"something went wrong.")
    IF (careful_mod) CALL timestop (error_handle)
#endif
  END SUBROUTINE dbcsr_acc_transpose

END MODULE dbcsr_acc_operations
