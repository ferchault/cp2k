!-----------------------------------------------------------------------------!
!   CP2K: A general program to perform molecular dynamics simulations         !
!   Copyright (C) 2000 - 2015  CP2K developers group                          !
!-----------------------------------------------------------------------------!

! *****************************************************************************
!> \brief provides a unified interface to lapack geev routines 
!> \par History
!>       2014.09 created [Florian Schiffmann]
!> \author Florian Schiffmann
! *****************************************************************************

MODULE dbcsr_geev
  USE dbcsr_error_handling,            ONLY: dbcsr_abort
  USE kinds,                           ONLY: real_4,&
                                             real_8
#include "../../base/base_uses.f90"

  IMPLICIT NONE

  PRIVATE

  CHARACTER(len=*), PARAMETER, PRIVATE :: moduleN = 'dbcsr_geev'

  PUBLIC :: dbcsr_general_local_diag, dbcsr_tridiag_local_diag, dbcsr_symm_local_diag

  INTERFACE dbcsr_general_local_diag
     MODULE PROCEDURE dbcsr_sgeev, dbcsr_dgeev, dbcsr_zgeev, dbcsr_cgeev
  END INTERFACE

  ! currently only specialzed for real matrices
  INTERFACE dbcsr_tridiag_local_diag
     MODULE PROCEDURE dbcsr_sstev, dbcsr_dstev, dbcsr_zgeev, dbcsr_cgeev
  END INTERFACE

  ! currently only specialzed for real matrices
  INTERFACE dbcsr_symm_local_diag
     MODULE PROCEDURE dbcsr_dsyevd, dbcsr_ssyevd, dbcsr_cheevd, dbcsr_zheevd
  END INTERFACE

CONTAINS

! *****************************************************************************
!> \brief ...
!> \param jobvr ...
!> \param matrix ...
!> \param ndim ...
!> \param evals ...
!> \param revec ...
! *****************************************************************************
  SUBROUTINE dbcsr_zheevd(jobvr,matrix,ndim,evals,revec)
    CHARACTER(1)                             :: jobvr
    COMPLEX(real_8), DIMENSION(:, :)         :: matrix
    INTEGER                                  :: ndim
    COMPLEX(real_8), DIMENSION(:)            :: evals
    COMPLEX(real_8), DIMENSION(:, :)         :: revec

    CHARACTER(LEN=*), PARAMETER :: routineN = 'dbcsr_zheevd', &
      routineP = moduleN//':'//routineN

    INTEGER                                  :: i, info, liwork, lrwork, &
                                                lwork, iwork(3+5*ndim)
    COMPLEX(real_8)                          :: work(2*ndim+ndim**2), &
                                                tmp_array(ndim,ndim)
    REAL(real_8)                             :: rwork(1+5*ndim+2*ndim**2)

    tmp_array(:,:)=matrix(:,:) 
    lwork=2*ndim+ndim**2
    lrwork=1+5*ndim+2*ndim**2
    liwork=3+5*ndim
    
    CALL zheevd(jobvr,'U',ndim,tmp_array,evals,ndim,work,lwork,rwork,lrwork,iwork,liwork,info)
    
    DO i=1,ndim
       revec(:,i)=tmp_array(:,i)
    END DO
   
  END SUBROUTINE dbcsr_zheevd

! *****************************************************************************
!> \brief ...
!> \param jobvr ...
!> \param matrix ...
!> \param ndim ...
!> \param evals ...
!> \param revec ...
! *****************************************************************************
  SUBROUTINE dbcsr_cheevd(jobvr,matrix,ndim,evals,revec)
    CHARACTER(1)                             :: jobvr
    COMPLEX(real_4), DIMENSION(:, :)         :: matrix
    INTEGER                                  :: ndim
    COMPLEX(real_4), DIMENSION(:)            :: evals
    COMPLEX(real_4), DIMENSION(:, :)         :: revec

    CHARACTER(LEN=*), PARAMETER :: routineN = 'dbcsr_cheevd', &
      routineP = moduleN//':'//routineN

    INTEGER                                  :: i, info, liwork, lrwork, &
                                                lwork, iwork(3+5*ndim)
    COMPLEX(real_4)                          :: work(2*ndim+ndim**2), &
                                                tmp_array(ndim,ndim)
    REAL(real_4)                             :: rwork(1+5*ndim+2*ndim**2)

    tmp_array(:,:)=matrix(:,:) 
    lwork=2*ndim+ndim**2
    lrwork=1+5*ndim+2*ndim**2
    liwork=3+5*ndim
    
    CALL zheevd(jobvr,'U',ndim,tmp_array,evals,ndim,work,lwork,rwork,lrwork,iwork,liwork,info)
    
    DO i=1,ndim
       revec(:,i)=tmp_array(:,i)       
    END DO
   
  END SUBROUTINE dbcsr_cheevd


! *****************************************************************************
!> \brief ...
!> \param jobvr ...
!> \param matrix ...
!> \param ndim ...
!> \param evals ...
!> \param revec ...
! *****************************************************************************
  SUBROUTINE dbcsr_dsyevd(jobvr,matrix,ndim,evals,revec)
    CHARACTER(1)                             :: jobvr
    REAL(real_8), DIMENSION(:, :)            :: matrix
    INTEGER                                  :: ndim
    COMPLEX(real_8), DIMENSION(:)            :: evals
    COMPLEX(real_8), DIMENSION(:, :)         :: revec

    CHARACTER(LEN=*), PARAMETER :: routineN = 'dbcsr_dsyevd', &
      routineP = moduleN//':'//routineN

    INTEGER                                  :: i, info, liwork, lwork, &
                                                iwork(3+5*ndim)
    REAL(real_8)                             :: tmp_array(ndim,ndim), &
                                                work(1+6*ndim+2*ndim**2)
    REAL(real_8), DIMENSION(ndim)            :: eval

    lwork=1+6*ndim+2*ndim**2
    liwork=3+5*ndim

    tmp_array(:,:)=matrix(:,:)
    CALL dsyevd(jobvr,"U",ndim,tmp_array,ndim,eval,work,lwork,iwork,liwork,info) 

    DO i=1,ndim
       revec(:,i)=CMPLX(tmp_array(:,i),REAL(0.0,real_8),real_8)
       evals(i)=CMPLX(eval(i),0.0,real_8)
    END DO    

  END SUBROUTINE dbcsr_dsyevd

! *****************************************************************************
!> \brief ...
!> \param jobvr ...
!> \param matrix ...
!> \param ndim ...
!> \param evals ...
!> \param revec ...
! *****************************************************************************
  SUBROUTINE dbcsr_ssyevd(jobvr,matrix,ndim,evals,revec)
    CHARACTER(1)                             :: jobvr
    REAL(real_4), DIMENSION(:, :)            :: matrix
    INTEGER                                  :: ndim
    COMPLEX(real_4), DIMENSION(:)            :: evals
    COMPLEX(real_4), DIMENSION(:, :)         :: revec

    CHARACTER(LEN=*), PARAMETER :: routineN = 'dbcsr_ssyevd', &
      routineP = moduleN//':'//routineN

    INTEGER                                  :: i, info, liwork, lwork, &
                                                iwork(3+5*ndim)
    REAL(real_4)                             :: tmp_array(ndim,ndim), &
                                                work(1+6*ndim+2*ndim**2)
    REAL(real_4), DIMENSION(ndim)            :: eval

    MARK_USED(jobvr) !the argument has to be here for the template to work
    lwork=1+6*ndim+2*ndim**2
    liwork=3+5*ndim

    tmp_array(:,:)=matrix(:,:)
    CALL ssyevd("V","U",ndim,tmp_array,ndim,eval,work,lwork,iwork,liwork,info)     

    DO i=1,ndim
       revec(:,i)=CMPLX(tmp_array(:,i),REAL(0.0,real_4),real_4)
       evals(i)=CMPLX(eval(i),0.0,real_4)
    END DO

  END SUBROUTINE dbcsr_ssyevd
 

! *****************************************************************************
!> \brief ...
!> \param jobvl ...
!> \param jobvr ...
!> \param matrix ...
!> \param ndim ...
!> \param evals ...
!> \param revec ...
!> \param levec ...
! *****************************************************************************
  SUBROUTINE dbcsr_sstev(jobvl,jobvr,matrix,ndim,evals,revec,levec)
    CHARACTER(1)                             :: jobvl, jobvr
    REAL(real_4), DIMENSION(:, :)            :: matrix
    INTEGER                                  :: ndim
    COMPLEX(real_4), DIMENSION(:)            :: evals
    COMPLEX(real_4), DIMENSION(:, :)         :: revec, levec

    CHARACTER(LEN=*), PARAMETER :: routineN = 'dbcsr_sstev', &
      routineP = moduleN//':'//routineN

    INTEGER                                  :: i, info
    REAL(real_4)                             :: work(20*ndim)
    REAL(real_4), DIMENSION(ndim)            :: diag, offdiag
    REAL(real_4), DIMENSION(ndim, ndim)      :: evec_r

    MARK_USED(jobvl) !the argument has to be here for the template to work

    levec(1,1)=CMPLX(0.0,0.0,real_4)
    info =0
    diag(ndim)=matrix(ndim,ndim)
    DO i=1,ndim-1
       diag(i)=matrix(i,i)
       offdiag(i)=matrix(i+1,i)
    END DO

    CALL sstev(jobvr,ndim,diag,offdiag,evec_r,ndim,work,info)

    DO i=1,ndim
       revec(:,i)=CMPLX(evec_r(:,i),REAL(0.0,real_4),real_4)
       evals(i)=CMPLX(diag(i),0.0,real_4)
    END DO
  END SUBROUTINE dbcsr_sstev


! *****************************************************************************
!> \brief ...
!> \param jobvl ...
!> \param jobvr ...
!> \param matrix ...
!> \param ndim ...
!> \param evals ...
!> \param revec ...
!> \param levec ...
! *****************************************************************************
  SUBROUTINE dbcsr_dstev(jobvl,jobvr,matrix,ndim,evals,revec,levec)
    CHARACTER(1)                             :: jobvl, jobvr
    REAL(real_8), DIMENSION(:, :)            :: matrix
    INTEGER                                  :: ndim
    COMPLEX(real_8), DIMENSION(:)            :: evals
    COMPLEX(real_8), DIMENSION(:, :)         :: revec, levec

    CHARACTER(LEN=*), PARAMETER :: routineN = 'dbcsr_dstev', &
      routineP = moduleN//':'//routineN

    INTEGER                                  :: i, info
    REAL(real_8)                             :: work(20*ndim)
    REAL(real_8), DIMENSION(ndim)            :: diag, offdiag
    REAL(real_8), DIMENSION(ndim, ndim)      :: evec_r

    MARK_USED(jobvl) !the argument has to be here for the template to work

    levec(1,1)=CMPLX(0.0,0.0,real_8)
    info =0
    diag(ndim)=matrix(ndim,ndim)
    DO i=1,ndim-1
       diag(i)=matrix(i,i)
       offdiag(i)=matrix(i+1,i)
  
    END DO
    
    CALL dstev(jobvr,ndim,diag,offdiag,evec_r,ndim,work,info)
   
    DO i=1,ndim
       revec(:,i)=CMPLX(evec_r(:,i),REAL(0.0,real_8),real_8)
       evals(i)=CMPLX(diag(i),0.0,real_8)
    END DO
  END SUBROUTINE dbcsr_dstev
! *****************************************************************************
!> \brief ...
!> \param jobvl ...
!> \param jobvr ...
!> \param matrix ...
!> \param ndim ...
!> \param evals ...
!> \param revec ...
!> \param levec ...
! *****************************************************************************
  SUBROUTINE dbcsr_sgeev(jobvl,jobvr,matrix,ndim,evals,revec,levec)
    CHARACTER(1)                             :: jobvl, jobvr
    REAL(real_4), DIMENSION(:, :)            :: matrix
    INTEGER                                  :: ndim
    COMPLEX(real_4), DIMENSION(:)            :: evals
    COMPLEX(real_4), DIMENSION(:, :)         :: revec, levec

    CHARACTER(LEN=*), PARAMETER :: routineN = 'dbcsr_sgeev', &
      routineP = moduleN//':'//routineN

    INTEGER                                  :: i, info, lwork
    LOGICAL                                  :: selects(ndim)
    REAL(real_4)                             :: norm, tmp_array(ndim,ndim), &
                                                work(20*ndim)
    REAL(real_4), DIMENSION(ndim)            :: eval1, eval2
    REAL(real_4), DIMENSION(ndim, ndim)      :: evec_l, evec_r

    MARK_USED(jobvr) !the argument has to be here for the template to work
    MARK_USED(jobvl) !the argument has to be here for the template to work

    eval1=REAL(0.0,real_4); eval2=REAL(0.0,real_4)
    tmp_array(:,:)=matrix(:,:)
    ! ask lapack how much space it would like in the work vector, don't ask me why
    lwork=-1
    CALL shseqr('S','I',ndim,1,ndim,tmp_array,ndim, eval1, eval2, evec_r, ndim,work,lwork,info)


    lwork=MIN(20*ndim, INT(work(1)))
    CALL shseqr('S','I',ndim,1,ndim,tmp_array,ndim, eval1, eval2, evec_r, ndim,work,lwork,info)
    CALL strevc('R','B',selects,ndim,tmp_array,ndim,evec_l,ndim,evec_r,ndim,ndim,ndim,work,info)

    ! compose the eigenvectors, lapacks way of storing them is a pain
    ! if eval is complex, then the complex conj pair of evec can be constructed from the i and i+1st evec
    ! Unfortunately dtrevc computes the ev such that the largest is set to one and not normalized
    i=1
    DO WHILE (i.le.ndim)
      IF(ABS(eval2(i)).LT.EPSILON(REAL(0.0,real_4)))THEN
        evec_r(:,i)=evec_r(:,i)/SQRT(DOT_PRODUCT(evec_r(:,i),evec_r(:,i)))
        revec(:,i)=CMPLX(evec_r(:,i),REAL(0.0,real_4),real_4)
        levec(:,i)=CMPLX(evec_l(:,i),REAL(0.0,real_4),real_4)
        i=i+1
      ELSE IF(eval2(i).GT.EPSILON(REAL(0.0,real_4)))THEN
        norm=SQRT(SUM(evec_r(:,i)**2.0_real_4)+SUM(evec_r(:,i+1)**2.0_real_4))
        revec(:,i)=CMPLX(evec_r(:,i),evec_r(:,i+1),real_4)/norm
        revec(:,i+1)=CMPLX(evec_r(:,i),-evec_r(:,i+1),real_4)/norm
        levec(:,i)=CMPLX(evec_l(:,i),evec_l(:,i+1),real_4)
        levec(:,i+1)=CMPLX(evec_l(:,i),-evec_l(:,i+1),real_4)
        i=i+2
      ELSE
        CALL dbcsr_abort(routineP,__LINE__,'something went wrong while sorting the EV in dbcsr_geev')
      END IF
    END DO

    ! this is to keep the interface consistent with complex geev
    DO i=1,ndim
       evals(i)=CMPLX(eval1(i),eval2(i),real_4)
    END DO

  END SUBROUTINE  dbcsr_sgeev

! *****************************************************************************
!> \brief ...
!> \param jobvl ...
!> \param jobvr ...
!> \param matrix ...
!> \param ndim ...
!> \param evals ...
!> \param revec ...
!> \param levec ...
! *****************************************************************************
  SUBROUTINE dbcsr_dgeev(jobvl,jobvr,matrix,ndim,evals,revec,levec)
    CHARACTER(1)                             :: jobvl, jobvr
    REAL(real_8), DIMENSION(:, :)            :: matrix
    INTEGER                                  :: ndim
    COMPLEX(real_8), DIMENSION(:)            :: evals
    COMPLEX(real_8), DIMENSION(:, :)         :: revec, levec

    CHARACTER(LEN=*), PARAMETER :: routineN = 'dbcsr_dgeev', &
      routineP = moduleN//':'//routineN

    INTEGER                                  :: i, info, lwork
    LOGICAL                                  :: selects(ndim)
    REAL(real_8)                             :: norm, tmp_array(ndim,ndim), &
                                                work(20*ndim)
    REAL(real_8), DIMENSION(ndim)            :: eval1, eval2
    REAL(real_8), DIMENSION(ndim, ndim)      :: evec_l, evec_r

    MARK_USED(jobvr) !the argument has to be here for the template to work
    MARK_USED(jobvl) !the argument has to be here for the template to work

    eval1=REAL(0.0,real_8); eval2=REAL(0.0,real_8)
    tmp_array(:,:)=matrix(:,:)
    ! ask lapack how much space it would like in the work vector, don't ask me why
    lwork=-1
    CALL dhseqr('S','I',ndim,1,ndim,tmp_array,ndim, eval1, eval2, evec_r, ndim,work,lwork,info)


    lwork=MIN(20*ndim, INT(work(1)))
    CALL dhseqr('S','I',ndim,1,ndim,tmp_array,ndim, eval1, eval2, evec_r, ndim,work,lwork,info)
    CALL dtrevc('R','B',selects,ndim,tmp_array,ndim,evec_l,ndim,evec_r,ndim,ndim,ndim,work,info)

    ! compose the eigenvectors, lapacks way of storing them is a pain
    ! if eval is complex, then the complex conj pair of evec can be constructed from the i and i+1st evec
    ! Unfortunately dtrevc computes the ev such that the largest is set to one and not normalized
    i=1
    DO WHILE (i.le.ndim)
      IF(ABS(eval2(i)).LT.EPSILON(REAL(0.0,real_8)))THEN
        evec_r(:,i)=evec_r(:,i)/SQRT(DOT_PRODUCT(evec_r(:,i),evec_r(:,i)))
        revec(:,i)=CMPLX(evec_r(:,i),REAL(0.0,real_8),real_8)
        levec(:,i)=CMPLX(evec_l(:,i),REAL(0.0,real_8),real_8)
        i=i+1
      ELSE IF(eval2(i).GT.EPSILON(REAL(0.0,real_8)))THEN
        norm=SQRT(SUM(evec_r(:,i)**2.0_real_8)+SUM(evec_r(:,i+1)**2.0_real_8))
        revec(:,i)=CMPLX(evec_r(:,i),evec_r(:,i+1),real_8)/norm
        revec(:,i+1)=CMPLX(evec_r(:,i),-evec_r(:,i+1),real_8)/norm
        levec(:,i)=CMPLX(evec_l(:,i),evec_l(:,i+1),real_8)
        levec(:,i+1)=CMPLX(evec_l(:,i),-evec_l(:,i+1),real_8)
        i=i+2
      ELSE
        CALL dbcsr_abort(routineP,__LINE__,'something went wrong while sorting the EV in dbcsr_geev')
      END IF
    END DO

    ! this is to keep the interface consistent with complex geev
    DO i=1,ndim
       evals(i)=CMPLX(eval1(i),eval2(i),real_8)
    END DO

  END SUBROUTINE  dbcsr_dgeev 

! *****************************************************************************
!> \brief ...
!> \param jobvl ...
!> \param jobvr ...
!> \param matrix ...
!> \param ndim ...
!> \param evals ...
!> \param revec ...
!> \param levec ...
! *****************************************************************************
  SUBROUTINE dbcsr_zgeev(jobvl,jobvr,matrix,ndim,evals,revec,levec)
    CHARACTER(1)                             :: jobvl, jobvr
    COMPLEX(real_8), DIMENSION(:, :)         :: matrix
    INTEGER                                  :: ndim
    COMPLEX(real_8), DIMENSION(:)            :: evals
    COMPLEX(real_8), DIMENSION(:, :)         :: revec, levec

    CHARACTER(LEN=*), PARAMETER :: routineN = 'dbcsr_zgeev', &
      routineP = moduleN//':'//routineN

    INTEGER                                  :: info, lwork
    COMPLEX(real_8)                          :: work(20*ndim), &
                                                tmp_array(ndim,ndim)
    REAL(real_8)                             :: work2(2*ndim)

    evals=CMPLX(0.0, 0.0, real_8) 
    ! ask lapack how much space it would like in the work vector, don't ask me why
    lwork=-1
    CALL ZGEEV(jobvl, jobvr, ndim, tmp_array, ndim, evals, levec, ndim, revec, ndim, work, lwork, work2, info)
    lwork=MIN(20*ndim, INT(work(1)))

    tmp_array(:,:)=matrix(:,:)
    CALL ZGEEV(jobvl, jobvr, ndim, tmp_array, ndim, evals, levec, ndim, revec, ndim, work, lwork, work2, info)

  END SUBROUTINE  dbcsr_zgeev 

! *****************************************************************************
!> \brief ...
!> \param jobvl ...
!> \param jobvr ...
!> \param matrix ...
!> \param ndim ...
!> \param evals ...
!> \param revec ...
!> \param levec ...
! *****************************************************************************
  SUBROUTINE dbcsr_cgeev(jobvl,jobvr,matrix,ndim,evals,revec,levec)
    CHARACTER(1)                             :: jobvl, jobvr
    COMPLEX(real_4), DIMENSION(:, :)         :: matrix
    INTEGER                                  :: ndim
    COMPLEX(real_4), DIMENSION(:)            :: evals
    COMPLEX(real_4), DIMENSION(:, :)         :: revec, levec

    CHARACTER(LEN=*), PARAMETER :: routineN = 'dbcsr_cgeev', &
      routineP = moduleN//':'//routineN

    INTEGER                                  :: info, lwork
    COMPLEX(real_4)                          :: work(20*ndim), &
                                                tmp_array(ndim,ndim)
    REAL(real_4)                             :: work2(2*ndim)

    evals=CMPLX(0.0, 0.0, real_4)
    ! ask lapack how much space it would like in the work vector, don't ask me why
    lwork=-1
    CALL CGEEV(jobvl, jobvr, ndim, tmp_array, ndim, evals, levec, ndim, revec, ndim, work, lwork, work2, info)
    lwork=MIN(20*ndim, INT(work(1)))

    tmp_array(:,:)=matrix(:,:)
    CALL CGEEV(jobvl, jobvr, ndim, tmp_array, ndim, evals, levec, ndim, revec, ndim, work, lwork, work2, info)

  END SUBROUTINE  dbcsr_cgeev

END MODULE dbcsr_geev 
