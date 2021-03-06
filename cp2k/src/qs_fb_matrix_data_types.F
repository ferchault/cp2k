!-----------------------------------------------------------------------------!
!   CP2K: A general program to perform molecular dynamics simulations         !
!   Copyright (C) 2000 - 2015  CP2K developers group                          !
!-----------------------------------------------------------------------------!

MODULE qs_fb_matrix_data_types

  USE kinds,                           ONLY: dp,&
                                             int_8
  USE qs_fb_hash_table_types,          ONLY: fb_hash_table_add,&
                                             fb_hash_table_create,&
                                             fb_hash_table_get,&
                                             fb_hash_table_has_data,&
                                             fb_hash_table_nullify,&
                                             fb_hash_table_obj,&
                                             fb_hash_table_release
#include "./common/cp_common_uses.f90"
#include "./base/base_uses.f90"

  IMPLICIT NONE

  PRIVATE

  ! public types
  PUBLIC :: fb_matrix_data_obj

  ! public methods
  PUBLIC :: fb_matrix_data_add,&
            fb_matrix_data_create,&
            fb_matrix_data_get,&
            fb_matrix_data_has_data,&
            fb_matrix_data_nullify,&
            fb_matrix_data_release

  CHARACTER(len=*), PARAMETER, PRIVATE :: moduleN = 'qs_fb_matrix_data_types'
  INTEGER, PRIVATE, SAVE :: last_fb_matrix_data_id = 0

  ! Parameters related to automatic resizing of matrix_data:
  ! Resize by EXPAND_FACTOR if total no. slots / no. of filled slots < ENLARGE_RATIO
  INTEGER, PARAMETER, PRIVATE :: ENLARGE_RATIO = 1
  INTEGER, PARAMETER, PRIVATE :: EXPAND_FACTOR = 2

! *****************************************************************************
!> \brief data type for one matrix block
!> \param data : pointer to matrix block
!> \author Lianheng Tong (LT) lianheng.tong@kcl.ac.uk
! *****************************************************************************
  TYPE fb_matrix_block
     REAL(KIND=dp), DIMENSION(:,:), POINTER :: p => NULL()
  END TYPE fb_matrix_block

! *****************************************************************************
!> \brief data type for storing a list of matrix blocks
!> \param nmax      : maximum number of blocks can be stored
!> \param nblks     : number of blocks currently stored
!> \param nencode   : integer used to encode global block coordinate (row, col)
!>                    into a single combined integer
!> \param ind       : hash table maping the global combined index of the blocks
!>                    to the location in the data area
!> \param blks      : data area, well the matrix elements are actuaally stored
!> \param id_nr     : unique id for the object
!> \param ref_count : reference counter for the object
!> \author Lianheng Tong (LT) lianheng.tong@kcl.ac.uk
! *****************************************************************************
  TYPE fb_matrix_data_data
     INTEGER :: id_nr, ref_count
     INTEGER :: nmax
     INTEGER :: nblks
     INTEGER :: nencode
     TYPE(fb_hash_table_obj) :: ind
     TYPE(fb_matrix_block), DIMENSION(:), POINTER :: blks => NULL()
  END TYPE fb_matrix_data_data

! *****************************************************************************
!> \brief the object container which allows for the creation of an array
!>        of pointers to fb_matrix_data objects
!> \param obj : pointer to the fb_matrix_data object
!> \author Lianheng Tong (LT) lianheng.tong@kcl.ac.uk
! *****************************************************************************
  TYPE fb_matrix_data_obj
     TYPE(fb_matrix_data_data), POINTER, PRIVATE :: obj => NULL()
  END TYPE fb_matrix_data_obj

CONTAINS

! *****************************************************************************
!> \brief Add a matrix block to a fb_matrix_data object
!> \param matrix_data : the fb_matrix_data object
!> \param row         : block row index of the matrix block
!> \param col         : block col index of the matrix block
!> \param blk         : the matrix block to add
!> \author Lianheng Tong (LT) lianheng.tong@kcl.ac.uk
! *****************************************************************************
  SUBROUTINE fb_matrix_data_add(matrix_data, row, col, blk)
    TYPE(fb_matrix_data_obj), INTENT(INOUT)  :: matrix_data
    INTEGER, INTENT(IN)                      :: row, col
    REAL(KIND=dp), DIMENSION(:, :), &
      INTENT(IN)                             :: blk

    CHARACTER(len=*), PARAMETER :: routineN = 'fb_matrix_data_add', &
      routineP = moduleN//':'//routineN

    INTEGER                                  :: existing_ii, ii, ncols, nrows
    INTEGER(KIND=int_8)                      :: pair_ind
    LOGICAL                                  :: check_ok, found

    check_ok = fb_matrix_data_has_data(matrix_data)
    CPASSERT(check_ok)
    ! check if we need to resize the blks array
    IF (matrix_data%obj%nblks*ENLARGE_RATIO .GE. &
        matrix_data%obj%nmax) THEN
       CALL fb_matrix_data_resize(matrix_data, &
                                  matrix_data%obj%nmax*EXPAND_FACTOR)
    END IF
    ! assign block, copy blk data instead of associate
    nrows = SIZE(blk, 1)
    ncols = SIZE(blk, 2)
    ! first check if the block already exists in matrix_data
    pair_ind = fb_matrix_data_encode_pair(row, col, matrix_data%obj%nencode)
    CALL fb_hash_table_get(matrix_data%obj%ind, pair_ind, existing_ii, found)
    IF (found) THEN
       ! matrix block aready stored, need to to reassign
       IF (ASSOCIATED(matrix_data%obj%blks(existing_ii)%p)) THEN
          DEALLOCATE(matrix_data%obj%blks(existing_ii)%p)
       END IF
       ALLOCATE(matrix_data%obj%blks(existing_ii)%p(nrows,ncols))
       matrix_data%obj%blks(existing_ii)%p(:,:) = blk(:,:)
    ELSE
       matrix_data%obj%nblks = matrix_data%obj%nblks + 1
       ii = matrix_data%obj%nblks
       ALLOCATE(matrix_data%obj%blks(ii)%p(nrows,ncols))
       matrix_data%obj%blks(ii)%p(:,:) = blk(:,:)
       ! record blk index in the index table
       CALL fb_hash_table_add(matrix_data%obj%ind, pair_ind, ii)
    END IF
  END SUBROUTINE fb_matrix_data_add

! *****************************************************************************
!> \brief Associates one fb_matrix_data object to another
!> \param a : the fb_matrix_data object to be associated
!> \param b : the fb_matrix_data object that a is to be associated to
!> \author Lianheng Tong (LT) lianheng.tong@kcl.ac.uk
! *****************************************************************************
  SUBROUTINE fb_matrix_data_associate(a, b)
    TYPE(fb_matrix_data_obj), INTENT(OUT)    :: a
    TYPE(fb_matrix_data_obj), INTENT(IN)     :: b

    a%obj => b%obj
  END SUBROUTINE fb_matrix_data_associate

! *****************************************************************************
!> \brief Creates and initialises an empty fb_matrix_data object of a given size
!> \param matrix_data : the fb_matrix_data object, its content must be NULL
!>                      and cannot be UNDEFINED
!> \param nmax        : max number of matrix blks can be stored
!> \param nencode ...
!> \author Lianheng Tong (LT) lianheng.tong@kcl.ac.uk
! *****************************************************************************
  SUBROUTINE fb_matrix_data_create(matrix_data, nmax, nencode)
    TYPE(fb_matrix_data_obj), INTENT(INOUT)  :: matrix_data
    INTEGER, INTENT(IN)                      :: nmax, nencode

    CHARACTER(len=*), PARAMETER :: routineN = 'fb_matrix_data_create', &
      routineP = moduleN//':'//routineN

    LOGICAL                                  :: check_ok

    check_ok = .NOT. fb_matrix_data_has_data(matrix_data)
    CPASSERT(check_ok)
    ALLOCATE(matrix_data%obj)
    CALL fb_hash_table_nullify(matrix_data%obj%ind)
    NULLIFY(matrix_data%obj%blks)
    matrix_data%obj%nmax = 0
    matrix_data%obj%nblks = 0
    matrix_data%obj%nencode = nencode
    CALL fb_matrix_data_init(matrix_data=matrix_data, &
                             nmax=nmax, &
                             nencode=nencode)
    ! book keeping stuff
    matrix_data%obj%ref_count = 1
    matrix_data%obj%id_nr = last_fb_matrix_data_id + 1
    last_fb_matrix_data_id = matrix_data%obj%id_nr
  END SUBROUTINE fb_matrix_data_create

! *****************************************************************************
!> \brief retrieve a matrix block from a matrix_data object
!> \param matrix_data : the fb_matrix_data object
!> \param row         : row index
!> \param col         : col index
!> \param blk_p       : pointer to the block in the fb_matrix_data object
!> \param found       : if the requested block exists in the fb_matrix_data
!>                      object
!> \author Lianheng Tong (LT) lianheng.tong@kcl.ac.uk
! *****************************************************************************
  SUBROUTINE fb_matrix_data_get(matrix_data, row, col, blk_p, found)
    TYPE(fb_matrix_data_obj), INTENT(IN)     :: matrix_data
    INTEGER, INTENT(IN)                      :: row, col
    REAL(KIND=dp), DIMENSION(:, :), POINTER  :: blk_p
    LOGICAL, INTENT(OUT)                     :: found

    CHARACTER(len=*), PARAMETER :: routineN = 'fb_matrix_data_get', &
      routineP = moduleN//':'//routineN

    INTEGER                                  :: ind_in_blk
    INTEGER(KIND=int_8)                      :: pair_ind
    LOGICAL                                  :: check_ok

    check_ok = fb_matrix_data_has_data(matrix_data)
    CPASSERT(check_ok)
    pair_ind = fb_matrix_data_encode_pair(row, col, matrix_data%obj%nencode)
    CALL fb_hash_table_get(matrix_data%obj%ind, pair_ind, ind_in_blk, found)
    IF (found) THEN
       blk_p => matrix_data%obj%blks(ind_in_blk)%p
    ELSE
       NULLIFY(blk_p)
    END IF
  END SUBROUTINE fb_matrix_data_get

! *****************************************************************************
!> \brief check if the object has data associated to it
!> \param matrix_data : the fb_matrix_data object in question
!> \retval res        : true if matrix_data%obj is associated, false otherwise
!> \author Lianheng Tong (LT) lianheng.tong@kcl.ac.uk
! *****************************************************************************
  PURE FUNCTION fb_matrix_data_has_data(matrix_data) RESULT(res)
    TYPE(fb_matrix_data_obj), INTENT(IN)     :: matrix_data
    LOGICAL                                  :: res

    res = ASSOCIATED(matrix_data%obj)
  END FUNCTION fb_matrix_data_has_data

! *****************************************************************************
!> \brief Initialises a fb_matrix_data object of a given size
!> \param matrix_data : the fb_matrix_data object, its content must be NULL
!>                      and cannot be UNDEFINED
!> \param nmax        : max number of matrix blocks can be stored, default is
!>                      to use the existing number of blocks in matrix_data
!> \param nencode     : integer used to incode (row, col) to a single combined
!>                      index
!> \author Lianheng Tong (LT) lianheng.tong@kcl.ac.uk
! *****************************************************************************
  SUBROUTINE fb_matrix_data_init(matrix_data, nmax, nencode)
    TYPE(fb_matrix_data_obj), INTENT(INOUT)  :: matrix_data
    INTEGER, INTENT(IN), OPTIONAL            :: nmax, nencode

    CHARACTER(len=*), PARAMETER :: routineN = 'fb_matrix_data_init', &
      routineP = moduleN//':'//routineN

    INTEGER                                  :: ii, my_nmax
    LOGICAL                                  :: check_ok

    check_ok = fb_matrix_data_has_data(matrix_data)
    CPASSERT(check_ok)
    my_nmax = matrix_data%obj%nmax
    IF (PRESENT(nmax)) my_nmax = nmax
    my_nmax = MAX(my_nmax, 1)
    IF (fb_hash_table_has_data(matrix_data%obj%ind)) THEN
       CALL fb_hash_table_release(matrix_data%obj%ind)
    END IF
    CALL fb_hash_table_create(matrix_data%obj%ind, my_nmax)
    IF (ASSOCIATED(matrix_data%obj%blks)) THEN
       DO ii = 1, SIZE(matrix_data%obj%blks)
          IF (ASSOCIATED(matrix_data%obj%blks(ii)%p)) THEN
             DEALLOCATE(matrix_data%obj%blks(ii)%p)
          END IF
       END DO
       DEALLOCATE(matrix_data%obj%blks)
    END IF
    ALLOCATE(matrix_data%obj%blks(my_nmax))
    matrix_data%obj%nmax = my_nmax
    ! nullify matrix blocks
    DO ii = 1, SIZE(matrix_data%obj%blks)
       NULLIFY(matrix_data%obj%blks(ii)%p)
    END DO
    matrix_data%obj%nblks = 0
    IF (PRESENT(nencode)) matrix_data%obj%nencode = nencode
  END SUBROUTINE fb_matrix_data_init

! *****************************************************************************
!> \brief Nullifies a fb_matrix_data object
!> \param matrix_data : the fb_matrix_data object
!> \author Lianheng Tong (LT) lianheng.tong@kcl.ac.uk
! *****************************************************************************
  PURE SUBROUTINE fb_matrix_data_nullify(matrix_data)
    TYPE(fb_matrix_data_obj), INTENT(INOUT)  :: matrix_data

    NULLIFY(matrix_data%obj)
  END SUBROUTINE fb_matrix_data_nullify

! *****************************************************************************
!> \brief releases given object
!> \param matrix_data : the fb_matrix_data object in question
!> \author Lianheng Tong (LT) lianheng.tong@kcl.ac.uk
! *****************************************************************************
  SUBROUTINE fb_matrix_data_release(matrix_data)
    TYPE(fb_matrix_data_obj), INTENT(INOUT)  :: matrix_data

    CHARACTER(len=*), PARAMETER :: routineN = 'fb_matrix_data_release', &
      routineP = moduleN//':'//routineN

    INTEGER                                  :: ii
    LOGICAL                                  :: check_ok

    IF (ASSOCIATED(matrix_data%obj)) THEN
       check_ok = matrix_data%obj%ref_count > 0
       CPASSERT(check_ok)
       matrix_data%obj%ref_count = matrix_data%obj%ref_count - 1
       IF (matrix_data%obj%ref_count == 0) THEN
          matrix_data%obj%ref_count = 1
          IF (fb_hash_table_has_data(matrix_data%obj%ind)) THEN
             CALL fb_hash_table_release(matrix_data%obj%ind)
          END IF
          IF (ASSOCIATED(matrix_data%obj%blks)) THEN
             DO ii = 1, SIZE(matrix_data%obj%blks)
                IF (ASSOCIATED(matrix_data%obj%blks(ii)%p)) THEN
                   DEALLOCATE(matrix_data%obj%blks(ii)%p)
                END IF
             END DO
             DEALLOCATE(matrix_data%obj%blks)
          END IF
          matrix_data%obj%ref_count = 0
          DEALLOCATE(matrix_data%obj)
       END IF
    ELSE
       NULLIFY(matrix_data%obj)
    END IF
  END SUBROUTINE fb_matrix_data_release

! *****************************************************************************
!> \brief retains given object
!> \param matrix_data : the fb_matrix_data object in question
!> \author Lianheng Tong (LT) lianheng.tong@kcl.ac.uk
! *****************************************************************************
  SUBROUTINE fb_matrix_data_retain(matrix_data)
    TYPE(fb_matrix_data_obj), INTENT(INOUT)  :: matrix_data

    CHARACTER(len=*), PARAMETER :: routineN = 'fb_matrix_data_retain', &
      routineP = moduleN//':'//routineN

    LOGICAL                                  :: check_ok

    check_ok = ASSOCIATED(matrix_data%obj)
    CPASSERT(check_ok)
    check_ok = matrix_data%obj%ref_count > 0
    CPASSERT(check_ok)
    matrix_data%obj%ref_count = matrix_data%obj%ref_count + 1
  END SUBROUTINE fb_matrix_data_retain

! *****************************************************************************
!> \brief Resize a fb_matrix_data object
!> \param matrix_data : the fb_matrix_data object
!> \param nmax        : new maximun size of matrix_data%obj%blks
!> \author Lianheng Tong (LT) lianheng.tong@kcl.ac.uk
! *****************************************************************************
  SUBROUTINE fb_matrix_data_resize(matrix_data, nmax)
    TYPE(fb_matrix_data_obj), INTENT(INOUT)  :: matrix_data
    INTEGER, INTENT(IN)                      :: nmax

    CHARACTER(len=*), PARAMETER :: routineN = 'fb_matrix_data_resize', &
      routineP = moduleN//':'//routineN

    INTEGER                                  :: ii, my_nmax
    LOGICAL                                  :: check_ok
    TYPE(fb_matrix_block), ALLOCATABLE, &
      DIMENSION(:)                           :: tmp_blks

    check_ok = fb_matrix_data_has_data(matrix_data)
    CPASSERT(check_ok)
    my_nmax = MAX(nmax, matrix_data%obj%nblks)
    ! resize the blks array, no need to reindex, as blks in the blks
    ! are always added to the array sequencially, and so their address
    ! do not change upon resizing.
    IF (ASSOCIATED(matrix_data%obj%blks)) THEN
       ALLOCATE(tmp_blks(matrix_data%obj%nblks))
       DO ii = 1, SIZE(tmp_blks)
          NULLIFY(tmp_blks(ii)%p)
       END DO
       DO ii = 1, matrix_data%obj%nblks
          tmp_blks(ii)%p => matrix_data%obj%blks(ii)%p
       END DO
       DEALLOCATE(matrix_data%obj%blks)
       ALLOCATE(matrix_data%obj%blks(my_nmax))
       DO ii = 1, SIZE(matrix_data%obj%blks)
          NULLIFY(matrix_data%obj%blks(ii)%p)
       END DO
       DO ii = 1, matrix_data%obj%nblks
          matrix_data%obj%blks(ii)%p => tmp_blks(ii)%p
       END DO
       DEALLOCATE(tmp_blks)
    ELSE
       ALLOCATE(matrix_data%obj%blks(my_nmax))
       DO ii = 1, SIZE(matrix_data%obj%blks)
          NULLIFY(matrix_data%obj%blks(ii)%p)
       END DO
    END IF
    matrix_data%obj%nmax = my_nmax
  END SUBROUTINE fb_matrix_data_resize

! *****************************************************************************
!> \brief outputs the current information about fb_matrix_data object
!> \param matrix_data : the fb_matrix_data object
!> \param nmax        : outputs fb_matrix_data%obj%nmax
!> \param nblks       : outputs fb_matrix_data%obj%nblks
!> \param nencode     : outputs fb_matrix_data%obj%nencode
!> \param blk_sizes   : blk_sizes(ii,jj) gives size of jj-th dim of the 
!>                      ii-th block stored 
!> \author Lianheng Tong (LT) lianheng.tong@kcl.ac.uk
! *****************************************************************************
  SUBROUTINE fb_matrix_data_status(matrix_data, nmax, nblks, nencode, blk_sizes)
    TYPE(fb_matrix_data_obj), INTENT(INOUT)  :: matrix_data
    INTEGER, INTENT(OUT), OPTIONAL           :: nmax, nblks, nencode
    INTEGER, DIMENSION(:, :), INTENT(OUT), &
      OPTIONAL                               :: blk_sizes

    CHARACTER(len=*), PARAMETER :: routineN = 'fb_matrix_data_status', &
      routineP = moduleN//':'//routineN

    INTEGER                                  :: ii
    LOGICAL                                  :: check_ok

    check_ok = fb_matrix_data_has_data(matrix_data)
    CPASSERT(check_ok)
    IF (PRESENT(nmax)) nmax = matrix_data%obj%nmax
    IF (PRESENT(nblks)) nblks = matrix_data%obj%nblks
    IF (PRESENT(nencode)) nencode = matrix_data%obj%nencode
    IF (PRESENT(blk_sizes)) THEN
       check_ok = (SIZE(blk_sizes, 1) .GE. matrix_data%obj%nblks .AND. &
                   SIZE(blk_sizes, 2) .GE. 2)
       CPASSERT(check_ok)
       blk_sizes(:,:) = 0
       DO ii = 1, matrix_data%obj%nblks
          blk_sizes(ii,1) = SIZE(matrix_data%obj%blks(ii)%p, 1)
          blk_sizes(ii,2) = SIZE(matrix_data%obj%blks(ii)%p, 2)
       END DO
    END IF
  END SUBROUTINE fb_matrix_data_status


! *****************************************************************************
!> \brief Encodes (row, col) index pair into a single combined index
!> \param row     : row index (assume to start counting from 1)
!> \param col     : col index (assume to start counting from 1)
!> \param nencode : integer used for encoding
!> \retval pair_ind : the returned value
!> \author Lianheng Tong (LT) lianheng.tong@kcl.ac.uk
! *****************************************************************************
  PURE FUNCTION fb_matrix_data_encode_pair(row, col, nencode) &
       RESULT(pair_ind)
    INTEGER, INTENT(IN)                      :: row, col, nencode
    INTEGER(KIND=int_8)                      :: pair_ind

    INTEGER(KIND=int_8)                      :: col_8, nencode_8, row_8

    row_8 = INT(row, int_8)
    col_8 = INT(col, int_8)
    nencode_8 = INT(nencode, int_8)
    pair_ind = (row_8 - 1_int_8) * nencode_8 + (col_8 - 1_int_8) + 1
  END FUNCTION fb_matrix_data_encode_pair

END MODULE qs_fb_matrix_data_types
