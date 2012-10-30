!listing00
! code licensed under the terms of GNU GPL v3
! copyright holder: University of Warsaw
!listing01
module arrvec_m
  implicit none

  type :: arr_t
    real, pointer :: a(:,:)
  end type

  type :: arrptr_t
    class(arr_t), pointer :: p
  end type

  type :: arrvec_t
    class(arrptr_t), pointer :: at(:)
    logical, pointer :: inited(:)
    contains
    procedure :: ctor => arrvec_ctor
    procedure :: init => arrvec_init
    procedure :: dtor => arrvec_dtor
  end type

  contains

  subroutine arrvec_ctor(this, n)
    class(arrvec_t) :: this
    integer, intent(in) :: n

    allocate(this%at(-n:n-1))
    allocate(this%inited(0:n-1))
    this%inited = .false.
  end subroutine

  subroutine arrvec_init(this, n,    &
    i_min, i_max, j_min, j_max       &
  )
    class(arrvec_t) :: this
    integer, intent(in) :: n,        &
      i_min, i_max, j_min, j_max

    allocate(this%at(n)%p)
    allocate(this%at(n)%p%a(         &
      i_min : i_max, j_min : j_max   &
    ))
    this%inited(n) = .true.
    this%at(n - size(this%inited))%p &
      => this%at(n)%p
  end subroutine

  subroutine arrvec_dtor(this)
    class(arrvec_t) :: this
    integer :: i

    do i = 0, size(this%inited) - 1
      if (this%inited(i)) then
        deallocate(this%at(i)%p%a)
        deallocate(this%at(i)%p)
      end if
    end do
    deallocate(this%at)
  end subroutine
end module
!listing02
module arakawa_c_m
  implicit none

  type :: half_t
  end type

  type(half_t) :: h

  interface operator (+)
    module procedure ph
  end interface

  interface operator (-)
    module procedure mh
  end interface

  contains

  elemental function ph(i, h) result (return)
    integer, intent(in) :: i
    type(half_t), intent(in) :: h
    integer :: return
    return = i + 1
  end function

  elemental function mh(i, h) result (return)
    integer, intent(in) :: i 
    type(half_t), intent(in) :: h
    integer :: return
    return = i
  end function
end module
!listing03
module adv_m
  use arrvec_m
  implicit none

  type, abstract :: adv_t
    integer :: n_steps, n_halos
    contains 
    procedure(op_2D_i), deferred :: op_2D
    procedure(adv_init_i), deferred :: init
  end type

  abstract interface
    subroutine op_2D_i(this, psi, n, C, step)
      import :: adv_t
      import :: arrvec_t
      class(adv_t) :: this
      class(arrvec_t), pointer :: psi, C
      integer, intent(in) :: n, step
    end subroutine

    subroutine adv_init_i(this, i, j)
      import :: adv_t
      class(adv_t) :: this
      integer, intent(in), pointer :: i(:), j(:)
    end subroutine
  end interface
end module
!listing04
module bcd_m
  use arrvec_m
  implicit none

  type, abstract :: bcd_t
    contains
    procedure(bcd_fill_halos_0_i), deferred :: fill_halos_0
    procedure(bcd_fill_halos_1_i), deferred :: fill_halos_1
    procedure(bcd_init_i), deferred :: init
  end type
 
  abstract interface 
    subroutine bcd_fill_halos_0_i(this, psi)
      import :: bcd_t
      class(bcd_t) :: this
      real, pointer :: psi(:,:)
    end subroutine
    subroutine bcd_fill_halos_1_i(this, psi)
      import :: bcd_t
      class(bcd_t) :: this
      real, pointer :: psi(:,:)
    end subroutine
    subroutine bcd_init_i(this, ij, hlo)
      import :: bcd_t
      class(bcd_t) :: this
      integer, pointer :: ij(:)
      integer :: hlo
    end subroutine
  end interface
end module
!listing05
module solver_2D_m
  use arrvec_m
  use adv_m
  use bcd_m
  implicit none

  type :: solver_2D_t
    class(arrvec_t), pointer :: psi, C
    class(adv_t), pointer :: adv
    class(bcd_t), pointer :: bcx, bcy
    integer, pointer :: i(:), j(:)
    integer :: n
    contains
    procedure :: ctor  => solver_2D_ctor 
    procedure :: solve => solver_2D_solve
    procedure :: state => solver_2D_state
    procedure :: Cx => solver_2D_Cx
    procedure :: Cy => solver_2D_Cy
    procedure :: dtor  => solver_2D_dtor 
  end type 

  contains

  subroutine solver_2D_ctor(this, nx,ny,adv,bcx,bcy)
    use arakawa_c_m
    class(solver_2D_t) :: this
    integer, intent(in) :: nx, ny
    class(adv_t), intent(in), pointer :: adv
    class(bcd_t), intent(in), pointer :: bcx, bcy

    allocate(this%i(0:nx-1), this%j(0:ny-1))
    block
      integer :: c
      this%i = (/ (c, c=0, nx-1) /)
      this%j = (/ (c, c=0, ny-1) /)
    end block

    call bcx%init(this%i, adv%n_halos)
    call bcy%init(this%j, adv%n_halos)
    call adv%init(this%i, this%j)

    block
      integer :: i, hlo
      hlo = adv%n_halos

      allocate(this%psi)
      call this%psi%ctor(2)
      
      do i=0, 1
        call this%psi%init(i, &
          this%i(0) -hlo, this%i(size(this%i)-1) + hlo, &
          this%j(0) -hlo, this%j(size(this%j)-1) + hlo  &
        ) 
      end do

      allocate(this%C)
      call this%C%ctor(2)
      call this%C%init(0,                                     &
        this%i(0) -hlo - h, this%i(size(this%i)-1) + hlo + h, &
        this%j(0) -hlo    , this%j(size(this%j)-1) + hlo      &   
      )
      call this%C%init(1,                                     &
        this%i(0) -hlo    , this%i(size(this%i)-1) + hlo,     &   
        this%j(0) -hlo - h, this%j(size(this%j)-1) + hlo + h  &
      )
    end block

    this%n = 0

    this%adv => adv
    this%bcx => bcx
    this%bcy => bcy
  end subroutine

  subroutine solver_2D_dtor(this)
    class(solver_2D_t) :: this
    call this%psi%dtor()
    deallocate(this%i, this%j, this%psi)
  end subroutine
  
  subroutine solver_2D_solve(this, nt)
    class(solver_2D_t) :: this
    integer, intent(in) :: nt

    block
      integer :: t, s 
      do t = 0, nt-1
        do s = 0, this%adv%n_steps-1
          call this%bcx%fill_halos_0(   &
            this%psi%at(this%n)%p%a)
          call this%bcy%fill_halos_1(   &
            this%psi%at(this%n)%p%a)
          call this%adv%op_2D(        &
            this%psi, this%n, this%C, s)
          this%n = mod(this%n + 1 + 2, 2) - 2
        end do
      end do
    end block
  end subroutine

  function solver_2D_state(this) result (return)
    class(solver_2D_t) :: this
    real, pointer :: return(:,:)
    return => this%psi%at(this%n)%p%a( &
      this%i(0) : this%i(size(this%i)-1), &
      this%j(0) : this%j(size(this%j)-1)  &
    )
  end function

  function solver_2D_Cx(this) result (return)
    class(solver_2D_t) :: this
    real, pointer :: return(:,:)
    return => this%C%at(0)%p%a
  end function

  function solver_2D_Cy(this) result (return)
    class(solver_2D_t) :: this
    real, pointer :: return(:,:)
    return => this%C%at(1)%p%a
  end function
end module
!listing06
module cyclic_m
  use bcd_m
  use adv_m
  implicit none
  
  type, extends(bcd_t) :: cyclic_t
    integer, pointer :: left_halo(:), rght_halo(:)
    integer, pointer :: left_edge(:), rght_edge(:)
    contains
    procedure :: init => cyclic_init
    procedure :: dtor => cyclic_dtor 
    procedure :: fill_halos_0 => cyclic_fill_halos_0
    procedure :: fill_halos_1 => cyclic_fill_halos_1
  end type

  contains

  subroutine cyclic_init(this, ij, hlo)
    class(cyclic_t) :: this
    integer, pointer :: ij(:)
    integer :: hlo
    allocate(this%left_halo(hlo))
    allocate(this%rght_halo(hlo))
    allocate(this%left_edge(hlo))
    allocate(this%rght_edge(hlo))

    block
      integer :: c
      this%left_halo = (/ (c, c = ij(0) - hlo, ij(0) - 1) /) 
      this%rght_halo = (/ (c, c = ij(size(ij)-1) + 1, ij(size(ij)-1) + hlo) /) 
      this%left_edge = (/ (c, c = ij(0),  ij(0) + hlo) /)
      this%rght_edge = (/ (c, c = ij(size(ij) - hlo), ij(size(ij)-1)) /)
    end block
  end subroutine

  subroutine cyclic_dtor(this)
    class(cyclic_t) :: this
    deallocate(this%left_halo)
    deallocate(this%rght_halo)
    deallocate(this%left_edge)
    deallocate(this%rght_edge)
  end subroutine

  subroutine cyclic_fill_halos_0(this, psi)
    class(cyclic_t) :: this
    real, pointer :: psi(:,:)
    psi(this%left_halo, :) = psi(this%rght_edge, :)
    psi(this%rght_halo, :) = psi(this%left_edge, :)
  end subroutine

  subroutine cyclic_fill_halos_1(this, psi)
    class(cyclic_t) :: this
    real, pointer :: psi(:,:)
    psi(:, this%left_halo) = psi(:, this%rght_edge)
    psi(:, this%rght_halo) = psi(:, this%left_edge)
  end subroutine
end module
!listing07
module donorcell_1D_m
  use arakawa_c_m
  implicit none
  contains 

  elemental function F(psi_l, psi_r, C) result (return)
    real :: return
    real, intent(in) :: psi_l, psi_r, C
    return = (                                 &
      .5 * (C + abs(C)) * psi_l +              &
      .5 * (C - abs(C)) * psi_r                &
    )
  end function
 
  function donorcell_0(psi, C, i, j) result (return)
    integer, pointer, intent(in) :: i(:), j(:)
    real :: return(i(0):i(size(i)-1),j(0):size(j)-1)
    real, pointer, intent(in) :: psi(:,:), C(:,:)
    return = (                                 &
      F(psi(i,   j), psi(i+1, j), C(i+h, j)) - &
      F(psi(i-1, j), psi(i,   j), C(i-h, j))   &
    )
  end function

  function donorcell_1(psi, C, i, j) result (return)
    integer, pointer, intent(in) :: i(:), j(:)
    real :: return(i(0):i(size(i)-1),j(0):j(size(j)-1))
    real, pointer, intent(in) :: psi(:,:), C(:,:)
    return = (                                 &
      F(psi(i, j  ), psi(i, j+1), C(i, j+h)) - &
      F(psi(i, j-1), psi(i,   j), C(i, j-h))   &
    )
  end function

end module
!
module donorcell_2D_m
  use donorcell_1D_m
  use arrvec_m
  implicit none
  contains 
  subroutine donorcell_2D(psi, n, C, i, j)  
    class(arrvec_t), pointer :: psi, C
    integer, intent(in) :: n
    integer, pointer, intent(in) :: i(:), j(:)
    
    psi%at( n+1 )%p%a( i, j ) = psi%at( n )%p%a( i, j ) &
      - donorcell_0(psi%at(n)%p%a, C%at(0)%p%a, i, j)   &
      - donorcell_1(psi%at(n)%p%a, C%at(1)%p%a, i, j)      
  end subroutine
end module
!
module antidiff_2D_m
  use arrvec_m
  use arakawa_c_m
  implicit none
  contains 
  function A_0(psi, i, j) result (return)
    real, pointer, intent(in) :: psi(:,:)
    integer, pointer :: i(:), j(:)
    real :: return(i(0):i(size(i)-1),j(0):j(size(j)-1))
    return = frac(             &
      psi(i+1, j) - psi(i, j), &
      psi(i+1, j) + psi(i, j)  &
    )  
  end function
  function A_1(psi, i, j) result (return)
    real, pointer, intent(in) :: psi(:,:)
    integer, pointer :: i(:), j(:)
    real :: return(i(0):i(size(i)-1),j(0):j(size(j)-1))
    return = frac(             &
      psi(i, j+1) - psi(i, j), &
      psi(i, j+1) + psi(i, j)  &
    )  
  end function
  function B_0(psi, i, j) result (return)
    real, pointer, intent(in) :: psi(:,:)
    integer, pointer :: i(:), j(:)
    real :: return(i(0):i(size(i)-1),j(0):j(size(j)-1))
    return = .5 * frac(   &
      psi(i+1, j+1)  &
    + psi(i,   j+1)  &
    - psi(i+1, j-1)  &
    - psi(i,   j-1), &
      psi(i+1, j+1)  &
    + psi(i,   j+1)  &
    + psi(i+1, j-1)  &
    + psi(i,   j-1)  &
    )
  end function
  function B_1(psi, i, j) result (return)
    real, pointer, intent(in) :: psi(:,:)
    integer, pointer :: i(:), j(:)
    real :: return(i(0):i(size(i)-1),j(0):j(size(j)-1))
    return = .5 * frac(   &
      psi(i+1, j+1)  &
    + psi(i+1, j  )  &
    - psi(i-1, j+1)  &
    - psi(i-1, j  ), &
      psi(i+1, j+1)  &
    + psi(i+1, j  )  &
    + psi(i-1, j+1)  &
    + psi(i-1, j  )  &
    )
  end function
  function frac(nom, den) result (return)
    real, intent(in) :: nom(:,:), den(:,:)
    real :: return(size(nom,1),size(nom,2))
    where (den > 0)
      return = nom / den
    elsewhere
      return = 0
    end where
  end function
  function antidiff_2D_0(psi, i, j, C) result (return)
    integer, pointer :: i(:), j(:)
    real :: return(i(0):i(size(i)-1),j(0):j(size(j)-1))
    real, pointer, intent(in) :: psi(:,:)
    class(arrvec_t), pointer :: C
    integer, parameter :: d = 0
 
    return =                           &
      abs(C%at(d)%p%a(i+h, j))         &
      * (1 - abs(C%at(d)%p%a(i+h, j))) &
      * A_0(psi, i, j)                 &
      - C%at(d)%p%a(i+h, j)            &
      * .25 * (                        &
        C%at(d-1)%p%a(i+1, j+h) +      &
        C%at(d-1)%p%a(i,   j+h) +      &
        C%at(d-1)%p%a(i+1, j-h) +      &
        C%at(d-1)%p%a(i,   j-h)        &
      )                                &
      * B_0(psi, i, j)
  end function
  function antidiff_2D_1(psi, i, j, C) result (return)
    integer, pointer :: i(:), j(:)
    real :: return(i(0):i(size(i)-1),j(0):j(size(j)-1))
    real, pointer, intent(in) :: psi(:,:)
    class(arrvec_t), pointer :: C
    integer, parameter :: d = 1
 
    return =                           &
      abs(C%at(d)%p%a(i, j+h))         &
      * (1 - abs(C%at(d)%p%a(i, j+h))) &
      * A_1(psi, i, j)                 &
      - C%at(d)%p%a(i, j+h)            &
      * .25 * (                        &
        C%at(d-1)%p%a(i+h, j+1) +      &
        C%at(d-1)%p%a(i+h, j  ) +      &
        C%at(d-1)%p%a(i-h, j+1) +      &
        C%at(d-1)%p%a(i-h, j  )        &
      )                                &
      * B_1(psi, i, j)
  end function
end module
!listing08
module mpdata_m
  use adv_m
  use donorcell_2D_m
  use antidiff_2D_m
  implicit none
  
  type, extends(adv_t) :: mpdata_t
    integer :: n_iters
    class(arrvec_t), pointer :: tmp(:) !TODO: dtor!
    integer, pointer :: i(:), j(:), im(:), jm(:)
    contains
    procedure :: ctor => mpdata_ctor
    procedure :: init => mpdata_init
    procedure :: op_2D => mpdata_op_2D
  end type

  contains

  subroutine mpdata_ctor(this, n_iters)
    class(mpdata_t) :: this
    integer, intent(in) :: n_iters
    this%n_iters = n_iters
    this%n_steps = n_iters
    this%n_halos = n_iters
  end subroutine 

  subroutine mpdata_init(this, i, j)
    class(mpdata_t) :: this
    integer, intent(in), pointer :: i(:), j(:)

    this%i => i
    this%j => j

    allocate(this%im(0:size(i)))  !TODO: deallocate
    allocate(this%jm(0:size(j)))  !TODO: deallocate
    block 
      integer :: c
      this%im = (/ (c, c=i(0)-1, j(size(i)-1)) /)
      this%jm = (/ (c, c=j(0)-1, j(size(j)-1)) /)
    end block
    
    block
      integer :: c, hlo, nc
      nc = 1
      if (this%n_iters > 2) nc = 2
      allocate(this%tmp(0:nc)) !TODO: deallocate?
      hlo = this%n_halos
      do c=0, nc-1
        call this%tmp(c)%ctor(2)
        call this%tmp(c)%init(0,                   &   
          i(0) -hlo - h, i(size(i)-1) + hlo + h, &
          j(0) -hlo    , j(size(j)-1) + hlo      &   
        )   
        call this%tmp(c)%init(1,                   &   
          i(0) -hlo    , i(size(i)-1) + hlo,     &   
          j(0) -hlo - h, j(size(j)-1) + hlo + h  &
        )  
      end do
    end block
  end subroutine

  subroutine mpdata_dtor(this)
    class(mpdata_t) :: this
    !TODO
    !deallocate()
  end subroutine

  subroutine mpdata_op_2D(this, psi, n, C, step)
    class(mpdata_t) :: this
    class(arrvec_t), pointer :: psi, C
    integer, intent(in) :: n, step

    if (step == 0) then
      call donorcell_2D(psi, n, C, this%i, this%j)
    else
      block
        class(arrvec_t), pointer :: C_corr, C_unco

        if (step == 1) then
          C_unco => C
          C_corr => this%tmp(0)
        else if (mod(step, 2) == 1) then
          C_unco => this%tmp(1)
          C_corr => this%tmp(0)
        else
          C_unco => this%tmp(0)
          C_corr => this%tmp(1)
        endif

        C_corr%at(0)%p%a(this%im+h, this%j) = &
          antidiff_2D_0(psi%at(n)%p%a, this%im, this%j, C_unco)
        C_corr%at(1)%p%a(this%i, this%jm+h) = &
          antidiff_2D_1(psi%at(n)%p%a, this%i, this%jm, C_unco)

        call donorcell_2D(psi, n, C_corr, this%i, this%j)
      end block
    endif

  end subroutine
end module
!listing09
