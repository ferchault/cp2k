!-----------------------------------------------------------------------------!
!   CP2K: A general program to perform molecular dynamics simulations         !
!   Copyright (C) 2000 - 2015  CP2K developers group                          !
!-----------------------------------------------------------------------------!

! *****************************************************************************
!> \brief calculates the electron transfer coupling elements
!>      Wu, Van Voorhis, JCP 125, 164105 (2006)
!> \author fschiff (01.2007)
! *****************************************************************************
MODULE et_coupling
  USE atomic_kind_types,               ONLY: atomic_kind_type,&
                                             get_atomic_kind_set
  USE cell_types,                      ONLY: cell_type
  USE cp_control_types,                ONLY: dft_control_type
  USE cp_dbcsr_interface,              ONLY: cp_dbcsr_deallocate_matrix_set,&
                                             cp_dbcsr_p_type
  USE cp_dbcsr_operations,             ONLY: cp_dbcsr_sm_fm_multiply
  USE cp_fm_basic_linalg,              ONLY: cp_fm_invert,&
                                             cp_fm_transpose
  USE cp_fm_pool_types,                ONLY: cp_fm_pool_p_type,&
                                             fm_pool_get_el_struct
  USE cp_fm_struct,                    ONLY: cp_fm_struct_type
  USE cp_fm_types,                     ONLY: cp_fm_create,&
                                             cp_fm_get_info,&
                                             cp_fm_p_type,&
                                             cp_fm_release,&
                                             cp_fm_type
  USE cp_gemm_interface,               ONLY: cp_gemm
  USE cp_output_handling,              ONLY: cp_print_key_finished_output,&
                                             cp_print_key_unit_nr
  USE cp_para_types,                   ONLY: cp_para_env_type
  USE input_constants,                 ONLY: do_spin_density
  USE input_section_types,             ONLY: section_vals_get_subs_vals,&
                                             section_vals_type
  USE kahan_sum,                       ONLY: accurate_sum
  USE kinds,                           ONLY: dp,&
                                             dp_size,&
                                             int_size
  USE mathlib,                         ONLY: diamat_all
  USE message_passing,                 ONLY: mp_sum
  USE particle_types,                  ONLY: particle_type
  USE pw_types,                        ONLY: pw_p_type
  USE qs_energy_types,                 ONLY: qs_energy_type
  USE qs_environment_types,            ONLY: get_qs_env,&
                                             qs_environment_type
  USE qs_force_types,                  ONLY: qs_force_type
  USE qs_matrix_pools,                 ONLY: mpools_get
  USE qs_mo_types,                     ONLY: get_mo_set
  USE qs_rho_types,                    ONLY: qs_rho_get,&
                                             qs_rho_type
  USE termination,                     ONLY: stop_memory
#include "./common/cp_common_uses.f90"
#include "./base/base_uses.f90"

  IMPLICIT NONE

  PRIVATE

  CHARACTER(len=*), PARAMETER, PRIVATE :: moduleN = 'et_coupling'

! *** Public subroutines ***

  PUBLIC :: calc_et_coupling, becke_restraint

CONTAINS
! *****************************************************************************
!> \brief ...
!> \param qs_env ...
! *****************************************************************************
  SUBROUTINE calc_et_coupling(qs_env)

    TYPE(qs_environment_type), POINTER       :: qs_env

    CHARACTER(len=*), PARAMETER :: routineN = 'calc_et_coupling', &
      routineP = moduleN//':'//routineN

    INTEGER                                  :: handle, i, iw, j, k, my_id, &
                                                nao, ncol_local, nmo, &
                                                nrow_local
    INTEGER, DIMENSION(:), POINTER           :: col_indices, row_indices
    REAL(KIND=dp)                            :: Sda, strength, Waa, Wbb, Wda
    REAL(KIND=dp), ALLOCATABLE, DIMENSION(:) :: a, b, S_det
    REAL(KIND=dp), DIMENSION(2)              :: eigenv
    REAL(KIND=dp), DIMENSION(2, 2)           :: S_mat, tmp_mat, U, W_mat
    TYPE(cp_dbcsr_p_type), DIMENSION(:), &
      POINTER                                :: matrix_s
    TYPE(cp_fm_p_type), DIMENSION(:), &
      POINTER                                :: rest_MO
    TYPE(cp_fm_pool_p_type), DIMENSION(:), &
      POINTER                                :: mo_mo_fm_pools
    TYPE(cp_fm_struct_type), POINTER         :: mo_mo_fmstruct
    TYPE(cp_fm_type), POINTER                :: inverse_mat, SMO, Tinverse, &
                                                tmp2
    TYPE(cp_logger_type), POINTER            :: logger
    TYPE(cp_para_env_type), POINTER          :: para_env
    TYPE(dft_control_type), POINTER          :: dft_control
    TYPE(qs_energy_type), POINTER            :: energy
    TYPE(section_vals_type), POINTER         :: et_coupling_section

    NULLIFY(tmp2,SMO,rest_MO,mo_mo_fmstruct,rest_MO,energy,matrix_s,dft_control,para_env)

    CALL timeset(routineN,handle)

    logger => cp_get_default_logger()
    et_coupling_section => section_vals_get_subs_vals(qs_env%input,&
                            "PROPERTIES%ET_COUPLING")

    CALL get_qs_env(qs_env, dft_control=dft_control, para_env=para_env)
    my_id=dft_control%qs_control%becke_control%density_type

    iw=cp_print_key_unit_nr(logger,et_coupling_section,"PROGRAM_RUN_INFO",&
                                         extension=".log")

    ALLOCATE(rest_MO(2))
    ALLOCATE(a(dft_control%nspins))
    ALLOCATE(b(dft_control%nspins))
    ALLOCATE(S_det(dft_control%nspins))

    CALL mpools_get(qs_env%mpools, mo_mo_fm_pools=mo_mo_fm_pools)
    mo_mo_fmstruct => fm_pool_get_el_struct(mo_mo_fm_pools(1)%pool)
    DO i=1, dft_control%nspins
    mo_mo_fmstruct => fm_pool_get_el_struct(mo_mo_fm_pools(i)%pool)

    CALL get_mo_set(mo_set=qs_env%mos(i)%mo_set,&
                    nao=nao,&
                    nmo=nmo)

    CALL cp_fm_create(matrix=tmp2,&
         matrix_struct=qs_env%mos(i)%mo_set%mo_coeff%matrix_struct,&
         name="ET_TMP"//TRIM(ADJUSTL(cp_to_string(2)))//"MATRIX")
    CALL cp_fm_create(matrix=inverse_mat,&
         matrix_struct=mo_mo_fmstruct,&
         name="INVERSE"//TRIM(ADJUSTL(cp_to_string(2)))//"MATRIX")
    CALL cp_fm_create(matrix=Tinverse,&
         matrix_struct=mo_mo_fmstruct,&
         name="T_INVERSE"//TRIM(ADJUSTL(cp_to_string(2)))//"MATRIX")
    CALL cp_fm_create(matrix=SMO,&
         matrix_struct=mo_mo_fmstruct,&
         name="ET_SMO"//TRIM(ADJUSTL(cp_to_string(1)))//"MATRIX")
    DO j=1,2
       NULLIFY(rest_MO(j)%matrix)
       CALL cp_fm_create(matrix=rest_MO(j)%matrix,&
            matrix_struct=mo_mo_fmstruct,&
            name="ET_rest_MO"//TRIM(ADJUSTL(cp_to_string(j)))//"MATRIX")
    END DO

!   calculate MO-overlap

    CALL get_qs_env(qs_env, matrix_s=matrix_s)
    CALL cp_dbcsr_sm_fm_multiply(matrix_s(1)%matrix,qs_env%et_coupling%et_mo_coeff(i)%matrix,&
         tmp2,nmo,1.0_dp,0.0_dp)
    CALL cp_gemm('T','N',nmo,nmo,nao,1.0_dp,&
         qs_env%mos(i)%mo_set%mo_coeff,&
         tmp2,0.0_dp,SMO)

!    calculate the MO-representation of the restraint matrix A

    CALL cp_dbcsr_sm_fm_multiply(qs_env%et_coupling%rest_mat(1)%matrix,&
         qs_env%et_coupling%et_mo_coeff(i)%matrix,&
         tmp2,nmo,1.0_dp,0.0_dp)

    CALL cp_gemm('T','N',nmo,nmo,nao,1.0_dp,&
         qs_env%mos(i)%mo_set%mo_coeff,&
         tmp2,0.0_dp,rest_MO(1)%matrix)

!    calculate the MO-representation of the restraint matrix D

    CALL cp_dbcsr_sm_fm_multiply(qs_env%et_coupling%rest_mat(2)%matrix,&
         qs_env%mos(i)%mo_set%mo_coeff,&
         tmp2,nmo,1.0_dp,0.0_dp)

    CALL cp_gemm('T','N',nmo,nmo,nao,1.0_dp,&
         qs_env%et_coupling%et_mo_coeff(i)%matrix,&
         tmp2,0.0_dp,rest_MO(2)%matrix)

   CALL cp_fm_invert(SMO,inverse_mat,S_det(i))

    CALL cp_fm_get_info(inverse_mat, nrow_local=nrow_local, ncol_local=ncol_local,&
                       row_indices=row_indices,col_indices=col_indices)
    b(i)=0.0_dp

    DO j=1,ncol_local
       DO k=1,nrow_local
          b(i)=b(i)+rest_MO(2)%matrix%local_data(k,j)*inverse_mat%local_data(k,j)
       END DO
    END DO

    CALL cp_fm_transpose(inverse_mat,Tinverse)
    a(i)=0.0_dp
    DO j=1,ncol_local
       DO k=1,nrow_local
          a(i)=a(i)+rest_MO(1)%matrix%local_data(k,j)*Tinverse%local_data(k,j)
       END DO
    END DO
    IF((my_id==do_spin_density).AND.i==2)THEN
       a(i)=-a(i)
       b(i)=-b(i)
    END IF
    CALL mp_sum(a(i), para_env%group)

    CALL mp_sum(b(i), para_env%group)

       CALL cp_fm_release(tmp2)
       CALL cp_fm_release(rest_MO(1)%matrix)
       CALL cp_fm_release(rest_MO(2)%matrix)
       CALL cp_fm_release(SMO)
       CALL cp_fm_release(Tinverse)
       CALL cp_fm_release(inverse_mat)
    END DO
    DEALLOCATE(rest_MO)

!    solve eigenstates for the projector matrix

    IF(dft_control%nspins ==2)THEN
       Sda=S_det(1)*S_det(2)
       Wda=((a(1)+a(2))+(b(1)+b(2)))*0.5_dp*Sda
    ELSE
       Sda=S_det(1)**2
       Wda=(a(1)+b(1))*Sda
    END IF

    IF(dft_control%qs_control%ddapc_restraint)THEN
    Waa=qs_env%et_coupling%order_p
    Wbb=dft_control%qs_control%ddapc_restraint_control(1)%ddapc_restraint_control%ddapc_order_p
    strength=dft_control%qs_control%ddapc_restraint_control(1)%ddapc_restraint_control%strength
    END IF
    IF(dft_control%qs_control%becke_restraint)THEN
    Waa=qs_env%et_coupling%order_p
    Wbb=dft_control%qs_control%becke_control%becke_order_p
    strength=dft_control%qs_control%becke_control%strength
    END IF

!!   construct S and W   !!!
    S_mat(1,1)=1.0_dp
    S_mat(2,2)=1.0_dp
    S_mat(2,1)=Sda
    S_mat(1,2)=Sda

    IF (iw>0) THEN
      WRITE(iw,'(/,(T3,A,T60,(3X,F12.6)))') 'Sda                               :',Sda
    ENDIF

    W_mat(1,1)=Wbb
    W_mat(2,2)=Waa
    W_mat(2,1)=Wda
    W_mat(1,2)=Wda

!!  solve WC=SCN
    CALL diamat_all (S_mat,eigenv,.TRUE.)
    ! U = S**(-1/2)
    U=0.0_dp
    U(1,1)=1.0_dp/SQRT(eigenv(1))
    U(2,2)=1.0_dp/SQRT(eigenv(2))
    tmp_mat=MATMUL(U,TRANSPOSE(S_mat))
    U=MATMUL(S_mat,tmp_mat)
    tmp_mat=MATMUL(W_mat,U)
    W_mat=MATMUL(U,tmp_mat)
    CALL diamat_all (W_mat,eigenv,.TRUE.)
    tmp_mat=MATMUL(U,W_mat)

    CALL get_qs_env(qs_env, energy=energy)
    W_mat(1,1)=energy%total
    W_mat(2,2)=qs_env%et_coupling%energy
    a(1)=(energy%total+strength*Wbb)*Sda-strength*Wda
    a(2)=(qs_env%et_coupling%energy+qs_env%et_coupling%e1*Waa)*Sda-qs_env%et_coupling%e1*Wda
    W_mat(1,2)=(a(1)+a(2))*0.5_dp
    W_mat(2,1)=W_mat(1,2)

    S_mat=MATMUL(W_mat,(tmp_mat))
    W_mat=MATMUL(TRANSPOSE(tmp_mat),S_mat)

    IF (iw>0) THEN
       WRITE(iw,*)
       WRITE(iw,'(T3,A,T60,(3X,F12.6))') 'Strength of constraint A          :',qs_env%et_coupling%e1
       WRITE(iw,'(T3,A,T60,(3X,F12.6))') 'Strength of constraint B          :',strength
       WRITE(iw,'(T3,A,T60,(3X,F12.6))') 'Final target value of constraint A:',Waa
       WRITE(iw,'(T3,A,T60,(3X,F12.6))') 'Final target value of constraint B:',Wbb
       WRITE(iw,*)
       WRITE(iw,'(T3,A,T60,(3X,F12.6))')&
            'Diabatic electronic coupling matrix element(mHartree):',ABS(W_mat(1,2)*1000.0_dp)

    ENDIF

    CALL cp_dbcsr_deallocate_matrix_set(qs_env%et_coupling%rest_mat)

    CALL cp_print_key_finished_output(iw,logger,et_coupling_section,&
               "PROGRAM_RUN_INFO")
    CALL timestop(handle)
  END SUBROUTINE calc_et_coupling

! *****************************************************************************
!> \brief calculates a becke contraint
!> \param qs_env ...
!> \param becke_const ...
!> \param calc_pot logical if potential has to be calculated or only_energy
!> \param calculate_forces ...
!> \author fschiff (01.2007)
! *****************************************************************************
  SUBROUTINE becke_restraint(qs_env,becke_const ,calc_pot,calculate_forces)

    TYPE(qs_environment_type), POINTER       :: qs_env
    TYPE(pw_p_type)                          :: becke_const
    LOGICAL                                  :: calc_pot, calculate_forces

    CHARACTER(len=*), PARAMETER :: routineN = 'becke_restraint', &
      routineP = moduleN//':'//routineN

    INTEGER                                  :: handle, i, iatom, ip, istat, &
                                                j, jatom, k, np(3)
    INTEGER, ALLOCATABLE, DIMENSION(:)       :: catom
    INTEGER, DIMENSION(2, 3)                 :: bo
    REAL(kind=dp)                            :: dE, dist1, dist2, dvol, my1, &
                                                myexp, strength, &
                                                sum_cell_f_all, &
                                                sum_cell_f_constr, target_val
    REAL(kind=dp), ALLOCATABLE, DIMENSION(:) :: cell_functions
    REAL(kind=dp), ALLOCATABLE, &
      DIMENSION(:, :)                        :: R12
    REAL(kind=dp), DIMENSION(3)              :: cell_v, dist_vec, dr, grid_p, &
                                                r, r1, shift
    REAL(kind=dp), DIMENSION(:), POINTER     :: coeff
    TYPE(cell_type), POINTER                 :: cell
    TYPE(cp_para_env_type), POINTER          :: para_env
    TYPE(dft_control_type), POINTER          :: dft_control
    TYPE(particle_type), DIMENSION(:), &
      POINTER                                :: particle_set
    TYPE(pw_p_type), DIMENSION(:), POINTER   :: rho_r
    TYPE(qs_energy_type), POINTER            :: energy
    TYPE(qs_rho_type), POINTER               :: rho

    NULLIFY(cell,particle_set,coeff,energy,rho,dft_control,para_env,rho_r)
    CALL timeset(routineN,handle)

    CALL get_qs_env(qs_env,&
                    cell=cell,&
                    particle_set=particle_set,&
                    rho=rho,&
                    dft_control=dft_control,&
                    para_env=para_env)

    CALL qs_rho_get(rho, rho_r=rho_r)

    IF (dft_control%qs_control%becke_restraint) THEN
          target_val=dft_control%qs_control%becke_control%target
          strength=dft_control%qs_control%becke_control%strength
          dvol = becke_const%pw%pw_grid%dvol
          IF(calc_pot)THEN


          becke_const%pw%cr3d=0.0_dp

          ALLOCATE (catom(dft_control%qs_control%becke_control%natoms),STAT=istat)
          IF (istat /= 0) CALL stop_memory(routineN,moduleN,__LINE__,&
                                           "catom",int_size*&
                                           dft_control%qs_control%becke_control%natoms)
          DO i=1,dft_control%qs_control%becke_control%natoms
             catom(i)=dft_control%qs_control%becke_control%atoms(i)
          ENDDO

          bo=becke_const%pw%pw_grid%bounds_local
          np=becke_const%pw%pw_grid%npts
          dvol = becke_const%pw%pw_grid%dvol
          dr=becke_const%pw%pw_grid%dr
          np= becke_const%pw%pw_grid%npts
          shift=-REAL(MODULO(np,2),dp)*dr/2.0_dp
          coeff => dft_control%qs_control%becke_control%coeff
          ALLOCATE (cell_functions(SIZE(particle_set)))
          !calculate distances from target atom (only implemented for a diatomic system)

          DO i=1,3
             cell_v(i)=cell%hmat(i,i)
          END DO

          ALLOCATE (R12(SIZE(particle_set), SIZE(particle_set)))

          DO iatom=1,SIZE(particle_set)-1
             DO jatom=iatom+1,SIZE(particle_set)
                r=particle_set(iatom)%r
                r1=particle_set(jatom)%r
                DO i=1,3
                   r(i)=MODULO(r(i),cell%hmat(i,i))-cell%hmat(i,i)/2._dp
                   r1(i)=MODULO(r1(i),cell%hmat(i,i))-cell%hmat(i,i)/2._dp
                END DO
                dist_vec=(r-r1)-ANINT((r-r1)/cell_v)*cell_v
                R12(iatom,jatom)=SQRT(DOT_PRODUCT(dist_vec,dist_vec))
                R12(jatom,iatom)=R12(iatom,jatom)
             END DO
          END DO

          DO k=bo(1,1),bo(2,1)
             DO j=bo(1,2),bo(2,2)
                DO i=bo(1,3),bo(2,3)
                   grid_p(1)=k*dr(1)+shift(1)
                   grid_p(2)=j*dr(2)+shift(2)
                   grid_p(3)=i*dr(3)+shift(3)

                   cell_functions=1.0_dp
                   DO iatom=1,SIZE(particle_set)
                      r=particle_set(iatom)%r
                      DO ip=1,3
                         r(ip)=MODULO(r(ip),cell%hmat(ip,ip))-cell%hmat(ip,ip)/2._dp
                      END DO
                      dist_vec=(r-grid_p)-ANINT((r-grid_p)/cell_v)*cell_v
                      dist1=SQRT(DOT_PRODUCT(dist_vec,dist_vec))
                      IF(dist1.LE.6.0_dp)THEN
                      DO jatom=1,SIZE(particle_set)
                         IF(jatom.NE.iatom)THEN
                         r1=particle_set(jatom)%r
                         DO ip=1,3
                            r1(ip)=MODULO(r1(ip),cell%hmat(ip,ip))-cell%hmat(ip,ip)/2._dp
                         END DO
                         dist_vec=(r1-grid_p)-ANINT((r1-grid_p)/cell_v)*cell_v
                         dist2=SQRT(DOT_PRODUCT(dist_vec,dist_vec))
                         my1= (dist1-dist2)/R12(iatom,jatom)
                         myexp=1.5_dp*my1-0.5_dp*my1**3
                         myexp=1.5_dp*myexp-0.5_dp*myexp**3
                         myexp=1.5_dp*myexp-0.5_dp*myexp**3
                         cell_functions(iatom)=cell_functions(iatom)*0.5_dp*(1-myexp)
                      END IF
                      END DO
                      ELSE
                         cell_functions(iatom)=0.0_dp
                      END IF
                   END DO

                   sum_cell_f_constr=0.0_dp
                   DO ip=1,dft_control%qs_control%becke_control%natoms
                      sum_cell_f_constr=sum_cell_f_constr+cell_functions(catom(ip))*coeff(ip)
                   END DO

                   sum_cell_f_all=0.0_dp
                   DO ip=1,SIZE(particle_set)
                      sum_cell_f_all=sum_cell_f_all+cell_functions(ip)
                   END DO
                   IF(ABS(sum_cell_f_all).LE.0.000001)THEN
                      becke_const%pw%cr3d(k,j,i)=0.0_dp
                   ELSE
                      becke_const%pw%cr3d(k,j,i)=sum_cell_f_constr/sum_cell_f_all
                   END IF

                END DO
             END DO
          END DO

          DEALLOCATE(catom)
          DEALLOCATE(R12)
          DEALLOCATE(cell_functions)

       END IF

       dE=0.0_dp
       DO i=1, dft_control%nspins
             dE=dE+accurate_sum(becke_const%pw%cr3d*rho_r(i)%pw%cr3d)*dvol
       END DO
       CALL get_qs_env(qs_env,energy=energy)
       CALL mp_sum(dE, para_env%group)
       dft_control%qs_control%becke_control%becke_order_p=dE
       energy%becke=(dE-target_val)*strength

       IF(calculate_forces) CALL becke_force(qs_env,becke_const)

    END IF
    CALL timestop(handle)
  END SUBROUTINE becke_restraint

! *****************************************************************************
!> \brief calculates a becke contraint forces
!> \param qs_env ...
!> \param becke_const ...
!> \author fschiff (01.2007)
! *****************************************************************************
  SUBROUTINE becke_force(qs_env,becke_const)

    TYPE(qs_environment_type), POINTER       :: qs_env
    TYPE(pw_p_type)                          :: becke_const

    CHARACTER(len=*), PARAMETER :: routineN = 'becke_force', &
      routineP = moduleN//':'//routineN

    INTEGER                                  :: handle, i, iatom, ikind, ip, &
                                                ispin, istat, j, jatom, k, &
                                                natom, np(3)
    INTEGER, ALLOCATABLE, DIMENSION(:)       :: atom_of_kind, catom, kind_of
    INTEGER, DIMENSION(2, 3)                 :: bo
    LOGICAL, ALLOCATABLE, DIMENSION(:)       :: is_constraint
    REAL(kind=dp) :: dist1, dist2, dpolyn, dvol, f_3, my1, polyn, strength, &
      sum_cell_f_constr, sum_Pm, target_val, th, tmp_const
    REAL(kind=dp), ALLOCATABLE, DIMENSION(:) :: coefficients, P_i
    REAL(kind=dp), ALLOCATABLE, &
      DIMENSION(:, :)                        :: d_sum_const_dR, d_sum_Pm_dR, &
                                                dP_i_dRi, dw_dR, integrated, &
                                                R12, s_my_ij
    REAL(kind=dp), ALLOCATABLE, &
      DIMENSION(:, :, :)                     :: dP_i_dRj, ds_dR
    REAL(kind=dp), DIMENSION(3) :: cell_v, dist_vec_i, dist_vec_j, dmy_dR_i, &
      dmy_dR_j, dr, dr1_r2, dr_i_dR, dr_ij_dR, dr_j_dR, grid_p, r, r1, shift
    TYPE(atomic_kind_type), DIMENSION(:), &
      POINTER                                :: atomic_kind_set
    TYPE(cell_type), POINTER                 :: cell
    TYPE(cp_para_env_type), POINTER          :: para_env
    TYPE(dft_control_type), POINTER          :: dft_control
    TYPE(particle_type), DIMENSION(:), &
      POINTER                                :: particle_set
    TYPE(pw_p_type), DIMENSION(:), POINTER   :: rho_r
    TYPE(qs_force_type), DIMENSION(:), &
      POINTER                                :: force
    TYPE(qs_rho_type), POINTER               :: rho

    CALL timeset(routineN,handle)
    NULLIFY(dft_control,cell,particle_set,para_env,rho_r)

    CALL get_qs_env(qs_env,&
                    atomic_kind_set=atomic_kind_set,&
                    natom=natom,&
                    particle_set=particle_set,&
                    cell=cell,&
                    rho=rho,&
                    force=force,&
                    dft_control=dft_control,&
                    para_env=para_env)


    CALL qs_rho_get(rho, rho_r=rho_r)

    th=1.0e-8_dp
    IF(dft_control%qs_control%becke_restraint)THEN

       target_val=dft_control%qs_control%becke_control%TARGET
       strength=dft_control%qs_control%becke_control%strength

       ALLOCATE (catom(dft_control%qs_control%becke_control%natoms),STAT=istat)
       IF (istat /= 0) CALL stop_memory(routineN,moduleN,__LINE__,&
                                        "catom",dp_size*dft_control%qs_control%becke_control%natoms)
       ALLOCATE (is_constraint(natom))
       ALLOCATE (coefficients(natom))

       is_constraint=.FALSE.
       DO i=1,dft_control%qs_control%becke_control%natoms
          catom(i)=dft_control%qs_control%becke_control%atoms(i)
          is_constraint(dft_control%qs_control%becke_control%atoms(i))=.TRUE.
          coefficients(catom(i))=dft_control%qs_control%becke_control%coeff(i)
       ENDDO

       ALLOCATE (atom_of_kind(natom),STAT=istat)
       IF (istat /= 0) CALL stop_memory(routineN,moduleN,__LINE__,&
                                        "atom_of_kind",natom*int_size)

       ALLOCATE (kind_of(natom),STAT=istat)
       IF (istat /= 0) CALL stop_memory(routineN,moduleN,__LINE__,&
                                        "kind_of",natom*int_size)

       CALL get_atomic_kind_set(atomic_kind_set=atomic_kind_set,&
                                atom_of_kind=atom_of_kind,&
                                kind_of=kind_of)

       bo=becke_const%pw%pw_grid%bounds_local
       np=becke_const%pw%pw_grid%npts
       dvol = becke_const%pw%pw_grid%dvol
       dr=becke_const%pw%pw_grid%dr
       np= becke_const%pw%pw_grid%npts
       shift=-REAL(MODULO(np,2),dp)*dr/2.0_dp
       !calculate distances from target atom (only implemented for a diatomic system)

       DO i=1,3
          cell_v(i)=cell%hmat(i,i)
       END DO

       ALLOCATE (R12(natom,natom))
       ALLOCATE (s_my_ij(natom, natom))
       ALLOCATE (ds_dR(3,natom,natom))
       ALLOCATE (P_i(natom))
       ALLOCATE (dw_dR(3,natom))
       ALLOCATE (integrated(3,natom))
       ALLOCATE (d_sum_Pm_dR(3,natom))
       ALLOCATE (d_sum_const_dR(3,natom))
       ALLOCATE (dP_i_dRj(3,natom,natom))
       ALLOCATE (dP_i_dRi(3,natom))

       DO iatom=1,natom-1
          DO jatom=iatom+1,natom
             r=particle_set(iatom)%r
             r1=particle_set(jatom)%r
             DO i=1,3
                r(i)=MODULO(r(i),cell%hmat(i,i))-cell%hmat(i,i)/2._dp
                r1(i)=MODULO(r1(i),cell%hmat(i,i))-cell%hmat(i,i)/2._dp
             END DO
             dist_vec_i=(r-r1)-ANINT((r-r1)/cell_v)*cell_v
             R12(iatom,jatom)=SQRT(DOT_PRODUCT(dist_vec_i,dist_vec_i))
             R12(jatom,iatom)=R12(iatom,jatom)
          END DO
       END DO

       integrated=0.0_dp

       DO k=bo(1,1),bo(2,1)
          DO j=bo(1,2),bo(2,2)
             DO i=bo(1,3),bo(2,3)
                grid_p(1)=k*dr(1)+shift(1)
                grid_p(2)=j*dr(2)+shift(2)
                grid_p(3)=i*dr(3)+shift(3)

                d_sum_Pm_dR=0.0_dp
                d_sum_const_dR=0.0_dp
                P_i=1.0_dp
                dP_i_dRi=0.0_dp
                DO iatom=1,natom
                   r=particle_set(iatom)%r
                   DO ip=1,3
                      r(ip)=MODULO(r(ip),cell%hmat(ip,ip))-cell%hmat(ip,ip)/2._dp
                   END DO
                   dist_vec_i=(r-grid_p)-ANINT((r-grid_p)/cell_v)*cell_v
                   dist1=SQRT(DOT_PRODUCT(dist_vec_i,dist_vec_i))
                   IF (dist1.LE.5.0_dp)THEN
                   IF(dist1.le.th)dist1=th
                   dr_i_dR(:)= dist_vec_i(:) / dist1
!                   IF(dist1.le.0.00001)dr_i_dR=0.0_dp
                   DO jatom=1,natom
                      IF (jatom.NE.iatom)THEN
                         r1=particle_set(jatom)%r
                         DO ip=1,3
                            r1(ip)=MODULO(r1(ip),cell%hmat(ip,ip))-cell%hmat(ip,ip)/2._dp
                         END DO
                         dist_vec_j= (r1-grid_p) -ANINT((r1-grid_p)/cell_v) *cell_v
                         dr1_r2=(r-r1) -ANINT((r-r1)/cell_v) *cell_v
                         dist2=SQRT(DOT_PRODUCT(dist_vec_j,dist_vec_j))
                         IF(dist2.LE.th)dist2=th
                         tmp_const = (R12(iatom,jatom)**3)
                         dr_ij_dR(:)= dr1_r2(:) / tmp_const

                         !derivativ w.r.t. Rj
                         dr_j_dR=dist_vec_j(:) / dist2

                         dmy_dR_j(:)= -(dr_j_dR(:) / R12(iatom,jatom) - (dist1-dist2) * dr_ij_dR(:))

                         !derivativ w.r.t. Ri
                         dmy_dR_i(:)= dr_i_dR(:) / R12(iatom,jatom) - (dist1-dist2) * dr_ij_dR(:)

                         my1= (dist1-dist2)/R12(iatom,jatom)
                         polyn= 1.5_dp * my1 - 0.5_dp * my1**3

                         dpolyn= 1.5_dp - 1.5_dp * my1**2

                         tmp_const = (1.5_dp**2)*(dpolyn-dpolyn*(polyn**2))-&
                                      (1.5_dp)*((1.5_dp*polyn-0.5*(polyn**3))**2)*&
                                      (1.5_dp*dpolyn-1.5_dp*dpolyn*(polyn**2))

                         ds_dR(:,iatom,jatom)=- 0.5_dp * tmp_const * dmy_dR_i(:)
                         ds_dR(:,jatom,iatom)=- 0.5_dp *tmp_const  * dmy_dR_j(:)
                         f_3 =  1.5_dp * polyn - 0.5_dp * polyn**3
                         f_3 =   1.5_dp * f_3 - 0.5_dp * f_3**3
                         s_my_ij(iatom,jatom)= 0.5_dp * (1-f_3)
                         P_i(iatom)= P_i(iatom) * s_my_ij(iatom,jatom)

                      END IF
                   END DO

                   DO jatom = 1,natom
                      IF(iatom.NE.jatom)THEN
                         IF(ABS( s_my_ij(iatom,jatom) ).LE.th)s_my_ij(iatom,jatom)=s_my_ij(iatom,jatom)+th

                         dP_i_dRi(:,iatom)= dP_i_dRi(:,iatom)+&
                              P_i(iatom) / s_my_ij(iatom,jatom) * ds_dR(:,iatom,jatom)
                         dP_i_dRj(:,iatom,jatom)= P_i(iatom) / s_my_ij(iatom,jatom) * ds_dR(:,jatom,iatom)

                      END IF
                   END DO
                   d_sum_Pm_dR(:,iatom)= d_sum_Pm_dR(:,iatom)+ dP_i_dRi(:,iatom)

                   IF(is_constraint(iatom)) d_sum_const_dR(:,iatom)= d_sum_const_dR(:,iatom)+ dP_i_dRi(:,iatom)*&
                                                                     coefficients(iatom)
                   DO jatom = 1,natom
                      IF(iatom.NE.jatom)THEN
                         d_sum_Pm_dR(:,jatom)=d_sum_Pm_dR(:,jatom)+ dP_i_dRj(:,iatom,jatom)

                         IF(is_constraint(iatom))d_sum_const_dR(:,jatom)= d_sum_const_dR(:,jatom)+ dP_i_dRj(:,iatom,jatom)*&
                                                                     coefficients(iatom)
                      END IF
                   END DO
                ELSE
                   P_i(iatom)=0.0_dp

                END IF

             END DO

             sum_Pm=0.0_dp
             DO ip=1,natom
                sum_Pm=sum_Pm+P_i(ip)
             END DO

             sum_cell_f_constr=0.0_dp
             DO ip=1,dft_control%qs_control%becke_control%natoms
                sum_cell_f_constr=sum_cell_f_constr+P_i(catom(ip)) * dft_control%qs_control%becke_control%coeff(ip)
             END DO

             DO iatom=1,natom
                IF(ABS(sum_Pm).EQ.0.0_dp)THEN
                   dw_dR(:,iatom)=0.0_dp
                ELSE
                   dw_dR(:,iatom)= d_sum_const_dR(:,iatom)/sum_Pm - &
                        sum_cell_f_constr * d_sum_Pm_dR(:,iatom) / (sum_Pm**2)
                END IF
             END DO

                DO iatom=1,natom
                   DO ispin=1, dft_control%nspins
                        integrated(:,iatom)=integrated(:,iatom) + dw_dR(:,iatom) * rho_r(ispin)%pw%cr3d(k,j,i) * dvol
                   END DO
                END DO
             END DO
          END DO
       END DO

       DEALLOCATE (catom)
       DEALLOCATE (R12)
       DEALLOCATE (s_my_ij)
       DEALLOCATE (ds_dR)
       DEALLOCATE (P_i)
       DEALLOCATE (dw_dR)
       DEALLOCATE (is_constraint)
       DEALLOCATE (d_sum_Pm_dR)
       DEALLOCATE (d_sum_const_dR)
       DEALLOCATE (dP_i_dRi)
       DEALLOCATE (dP_i_dRj)
       DEALLOCATE (coefficients)
       CALL mp_sum(integrated, para_env%group)

       DO iatom=1,natom
          ikind = kind_of(iatom)
          i = atom_of_kind(iatom)
          force(ikind)%rho_elec(:,i) =&
               force(ikind)%rho_elec(:,i) + integrated(:,iatom)*strength
       END DO

       DEALLOCATE (integrated)
       DEALLOCATE (atom_of_kind)
       DEALLOCATE (kind_of)

     END IF

     CALL timestop(handle)

  END SUBROUTINE becke_force

END MODULE et_coupling

