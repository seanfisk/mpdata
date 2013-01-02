#listing00
# code licensed under the terms of GNU GPL v3
# copyright holder: University of Warsaw
#listing01
real_t = 'float64'
#listing02
try:
  import numpypy
  from _numpypy.pypy import set_invalidation
  set_invalidation(False)
except ImportError:
  pass
import numpy
try: 
  numpy.seterr(all='ignore')
except AttributeError:
  pass
#listing03
class Shift():
  def __init__(self, plus, mnus):
    self.plus = plus
    self.mnus = mnus
  def __radd__(self, arg): 
    return type(arg)(
      arg.start + self.plus, 
      arg.stop  + self.plus
    )
  def __rsub__(self, arg): 
    return type(arg)(
      arg.start - self.mnus, 
      arg.stop  - self.mnus
    )
#listing04
one = Shift(1,1) 
hlf = Shift(0,1)
#listing05
def ext(r, n):
  if (type(n) == int) & (n == 1): 
    n = one
  return slice(
    (r - n).start, 
    (r + n).stop
  )
#listing06
def pi(d, *idx): 
  return (idx[d], idx[d-1])
#listing07
class Solver(object):
  # ctor-like method
  def __init__(self, bcx, bcy, nx, ny, hlo):
    self.n = 0
    self.hlo = hlo
    self.i = slice(hlo, nx + hlo)
    self.j = slice(hlo, ny + hlo)

    self.bcx = bcx(0, self.i, hlo)
    self.bcy = bcy(1, self.j, hlo)

    assert ext(self.i, self.hlo).start == 0
    assert ext(self.j, self.hlo).start == 0
    self.psi = (
      numpy.empty((
        ext(self.i, self.hlo).stop, 
        ext(self.j, self.hlo).stop
      ), real_t),
      numpy.empty((
        ext(self.i, self.hlo).stop, 
        ext(self.j, self.hlo).stop
      ), real_t)
    )

    assert ext(self.i, hlf).start == 0
    assert ext(self.j, hlf).start == 0
    self.C = (
      numpy.empty((
        ext(self.i, hlf).stop, 
        ext(self.j, self.hlo).stop
      ), real_t),
      numpy.empty((
        ext(self.i, self.hlo).stop, 
        ext(self.j, hlf).stop
      ), real_t)
    )

  # accessor methods
  def state(self):
    return self.psi[self.n][self.i, self.j]

  # helper methods invoked by solve()
  def courant(self,d):
    return self.C[d][:]

  def cycle(self):
    self.n  = (self.n + 1) % 2 - 2

   # integration logic
  def solve(self, nt):
    for t in range(nt):
      self.bcx.fill_halos(
        self.psi[self.n], ext(self.j, self.hlo)
      )
      self.bcy.fill_halos(
        self.psi[self.n], ext(self.i, self.hlo)
      )
      self.advop() 
      self.cycle()
  
#listing08
class Cyclic(object):
  # ctor
  def __init__(self, d, i, hlo): 
    self.d = d
    self.left_halo = slice(i.start-hlo, i.start    )
    self.rght_edge = slice(i.stop -hlo, i.stop     )
    self.rght_halo = slice(i.stop,      i.stop +hlo)
    self.left_edge = slice(i.start,     i.start+hlo)

  # method invoked by the solver
  def fill_halos(self, psi, j):
    psi[pi(self.d, self.left_halo, j)] = (
      psi[pi(self.d, self.rght_edge, j)]
    )
    psi[pi(self.d, self.rght_halo, j)] = (
      psi[pi(self.d, self.left_edge, j)]
    )

#listing09
def f(psi_l, psi_r, C):
  return (
    (C + abs(C)) * psi_l + 
    (C - abs(C)) * psi_r
  ) / 2
#listing10
def donorcell(d, psi, C, i, j):
  return (
    f(
      psi[pi(d, i,     j)], 
      psi[pi(d, i+one, j)], 
        C[pi(d, i+hlf, j)]
    ) - 
    f(
      psi[pi(d, i-one, j)], 
      psi[pi(d, i,     j)], 
        C[pi(d, i-hlf, j)]
    ) 
  )
#listing11
def donorcell_op(psi, n, C, i, j):
  psi[n+1][i,j] = (psi[n][i,j] 
    - donorcell(0, psi[n], C[0], i, j)
    - donorcell(1, psi[n], C[1], j, i)
  )
#listing12
class Donorcell(Solver):
  def __init__(self, bcx, bcy, nx, ny):
    Solver.__init__(self, bcx, bcy, nx, ny, 1)

  def advop(self):
    donorcell_op(
      self.psi, self.n, 
      self.C, self.i, self.j
    )
#listing13
def frac(nom, den):
  return numpy.where(den > 0, nom/den, 0)
#listing14
def a_op(d, psi, i, j):
  return frac(
    psi[pi(d, i+one, j)] - psi[pi(d, i, j)],
    psi[pi(d, i+one, j)] + psi[pi(d, i, j)]
  )
#listing15
def b_op(d, psi, i, j):
  return frac( 
    psi[pi(d, i+one, j+one)] + psi[pi(d, i, j+one)] -
    psi[pi(d, i+one, j-one)] - psi[pi(d, i, j-one)],
    psi[pi(d, i+one, j+one)] + psi[pi(d, i, j+one)] +
    psi[pi(d, i+one, j-one)] + psi[pi(d, i, j-one)]
  ) / 2
#listing16
def C_bar(d, C, i, j):
  return (
    C[pi(d, i+one, j+hlf)] + C[pi(d, i,  j+hlf)] +
    C[pi(d, i+one, j-hlf)] + C[pi(d, i,  j-hlf)] 
  ) / 4
#listing17
def antidiff(d, psi, i, j, C):
  return (
    abs(C[d][pi(d, i+hlf, j)]) 
    * (1 - abs(C[d][pi(d, i+hlf, j)])) 
    * a_op(d, psi, i, j)
    - C[d][pi(d, i+hlf, j)] 
    * C_bar(d, C[d-1], i, j)
    * b_op(d, psi, i, j)
  )
#listing18
class Mpdata(Solver):
  def __init__(self, n_iters, bcx, bcy, nx, ny):
    Solver.__init__(self, bcx, bcy, nx, ny, 1)
    self.im = slice(self.i.start-1, self.i.stop)
    self.jm = slice(self.j.start-1, self.j.stop)

    self.n_iters = n_iters
  
    self.tmp = [(
      numpy.empty(self.C[0].shape, real_t),
      numpy.empty(self.C[1].shape, real_t)
    )]
    if n_iters > 2:
      self.tmp.append((
        numpy.empty(self.C[0].shape, real_t),
        numpy.empty(self.C[1].shape, real_t)
      ))

  def advop(self):
    for step in range(self.n_iters):
      if step == 0:
        donorcell_op(
          self.psi, self.n, self.C, self.i, self.j
        )
      else:
        self.cycle()
        self.bcx.fill_halos(
          self.psi[self.n], ext(self.j, self.hlo)
        )
        self.bcy.fill_halos(
          self.psi[self.n], ext(self.i, self.hlo)
        )
        if step == 1:
          C_unco, C_corr = self.C, self.tmp[0]
        elif step % 2:
          C_unco, C_corr = self.tmp[1], self.tmp[0]
        else:
          C_unco, C_corr = self.tmp[0], self.tmp[1]

        C_corr[0][self.im+hlf, self.j] = (
          antidiff(0, self.psi[self.n], 
            self.im, self.j, C_unco)
          ) 
        self.bcy.fill_halos(C_corr[0], self.im)
        
        C_corr[1][self.i, self.jm+hlf] = (
          antidiff(1, self.psi[self.n], 
            self.jm, self.i, C_unco)
          ) 
        self.bcx.fill_halos(C_corr[1], self.jm)

        donorcell_op(
          self.psi, self.n, C_corr, self.i, self.j
        )
#listing19
