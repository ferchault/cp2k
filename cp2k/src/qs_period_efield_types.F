!-----------------------------------------------------------------------------!
!   CP2K: A general program to perform molecular dynamics simulations         !
!   Copyright (C) 2000 - 2015  CP2K developers group                          !
!-----------------------------------------------------------------------------!

! *****************************************************************************
!> \brief type for berry phase efield matrices. At the moment only used for
!>        cosmat and sinmat
!> \par History
!>      none
!> \author fschiff (06.2010)
! *****************************************************************************

MODULE qs_period_efield_types

  USE cp_dbcsr_interface,              ONLY: cp_dbcsr_deallocate_matrix_set,&
                                             cp_dbcsr_p_type
  USE kinds,                           ONLY: dp
#include "./common/cp_common_uses.f90"
#include "./base/base_uses.f90"

  IMPLICIT NONE

  PRIVATE

  CHARACTER(len=*), PARAMETER, PRIVATE :: moduleN = 'qs_period_efield_types'

  PUBLIC :: efield_berry_type, efield_berry_release, init_efield_matrices,&
            set_efield_matrices

  TYPE efield_berry_type
     REAL(KIND=dp)                                         :: field_energy
     REAL(KIND=dp), DIMENSION(3)                           :: polarisation
     TYPE(cp_dbcsr_p_type),DIMENSION(:), POINTER           :: cosmat
     TYPE(cp_dbcsr_p_type),DIMENSION(:), POINTER           :: sinmat
     TYPE(cp_dbcsr_p_type),DIMENSION(:), POINTER           :: dipmat
  END TYPE efield_berry_type

CONTAINS


! *****************************************************************************
!> \brief ...
!> \param efield ...
! *****************************************************************************
  SUBROUTINE init_efield_matrices(efield)
    TYPE(efield_berry_type), POINTER         :: efield

    CHARACTER(len=*), PARAMETER :: routineN = 'init_efield_matrices', &
      routineP = moduleN//':'//routineN

    REAL(KIND=dp)                            :: field_energy
    REAL(KIND=dp), DIMENSION(3)              :: polarisation

! retain possible values for energy and polarisation

    IF(ASSOCIATED(efield)) THEN
       field_energy = efield%field_energy
       polarisation = efield%polarisation
       CALL efield_berry_release(efield)
    ELSE
       field_energy = 0.0_dp
       polarisation = 0.0_dp
    END IF

    ALLOCATE(efield)
    NULLIFY(efield%cosmat)
    NULLIFY(efield%sinmat)
    NULLIFY(efield%dipmat)

    efield%field_energy = field_energy
    efield%polarisation = polarisation

  END SUBROUTINE init_efield_matrices

! *****************************************************************************
!> \brief ...
!> \param efield ...
!> \param sinmat ...
!> \param cosmat ...
!> \param dipmat ...
! *****************************************************************************
  SUBROUTINE set_efield_matrices(efield,sinmat,cosmat,dipmat)

    TYPE(efield_berry_type), POINTER         :: efield
    TYPE(cp_dbcsr_p_type), DIMENSION(:), &
      OPTIONAL, POINTER                      :: sinmat, cosmat, dipmat

    CHARACTER(len=*), PARAMETER :: routineN = 'set_efield_matrices', &
      routineP = moduleN//':'//routineN

     IF(PRESENT(cosmat))efield%cosmat=>cosmat
     IF(PRESENT(sinmat))efield%sinmat=>sinmat
     IF(PRESENT(dipmat))efield%dipmat=>dipmat

  END SUBROUTINE set_efield_matrices

! *****************************************************************************
!> \brief ...
!> \param efield ...
! *****************************************************************************
  SUBROUTINE efield_berry_release(efield)
    TYPE(efield_berry_type), POINTER         :: efield

    CHARACTER(len=*), PARAMETER :: routineN = 'efield_berry_release', &
      routineP = moduleN//':'//routineN

    IF(ASSOCIATED(efield))THEN
       IF(ASSOCIATED(efield%sinmat).AND.ASSOCIATED(efield%cosmat))THEN
          CALL cp_dbcsr_deallocate_matrix_set ( efield%cosmat)
          CALL cp_dbcsr_deallocate_matrix_set ( efield%sinmat)
       END IF
       IF(ASSOCIATED(efield%dipmat))THEN
          CALL cp_dbcsr_deallocate_matrix_set ( efield%dipmat)
       END IF
       DEALLOCATE(efield)
    END IF
  END SUBROUTINE efield_berry_release

END MODULE qs_period_efield_types
