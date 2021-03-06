#! /usr/bin/env python
import numpy as np
import h5py
from scipy.interpolate import interp1d
from scipy.stats import skewnorm

from hodpy.cosmology import CosmologyMXXL
from hodpy.catalogue import Catalogue
from hodpy.mass_function import MassFunctionMXXL
from hodpy import lookup

from abacusnbody.data.compaso_halo_catalog import CompaSOHaloCatalog


class HaloCatalogue(Catalogue):
    """
    Parent class for a halo catalogue
    """
    def __init__(self, cosmology, position, velocity, mass, rvmax):
        self._quantities = {'pos':   position,
                            'vel':   velocity,
                            'mass':  mass,
                            'rvmax': rvmax}
        self.size = len(mass)
        self.cosmology = cosmology
    
    
    def get(self, prop):
        """
        Get property from catalogue

        Args:
            prop: string of the name of the property
        Returns:
            array of property
        """
        # calculate properties not directly stored
        if prop == "log_mass":
            return np.log10(self._quantities["mass"])
        elif prop == "r200":
            return self.get_r200()
        elif prop == "conc":
            return self.get_concentration()
        elif prop == "mod_conc":
            return self.get_modified_concentration()
        elif prop == "conc_rs":
            return self.get_concentration_rs()
        
        # property directly stored
        return self._quantities[prop]


    def get_r200(self, comoving=True):
        """
        Returns R200mean of each halo

        Args:
            comoving: (optional) if True convert to comoving distance
        Returns:
            array of R200mean [Mpc/h]
        """
        rho_mean = self.cosmology.mean_density(self.get("zcos"))
        r200 = (3./(800*np.pi) * self.get("mass") / rho_mean)**(1./3)
        
        if comoving:
            return r200 * (1.+self.get("zcos"))
        else:
            return r200
    

    def get_concentration(self):
        """
        Returns NFW concentration of each halo, calculated from
        R200 and RVmax

        Returns:
            array of halo concentrations
        """
        conc = 2.16 * self.get("r200") / self.get("rvmax")

        return np.clip(conc, 0.1, 1e4)
    
    
    def get_concentration_rs(self):
        """
        Returns NFW concentration of each halo, calculated from
        R200 and Rs

        Returns:
            array of halo concentrations
        """
        conc = self.get("r200") / self.get("rs")

        return np.clip(conc, 0.1, 1e4)


    def get_modified_concentration(self):
        """
        Returns NFW concentration of each halo, modified to
        produce the right small scale clustering 
        (see Smith et al 2017)

        Returns:
            array of halo concentrations
        """
        # concentration from R200 and RVmax
        conc = self.get_concentration()
        conc_mod = np.zeros(len(conc))

        # mass bins
        mass_bins = np.arange(10, 16, 0.01)
        mass_bin_cen = mass_bins[:-1]+ 0.005
        logc_neto_mean = np.log10(4.67) - 0.11*(mass_bin_cen - 14)

        log_mass = self.get("log_mass")
        # loop through mass bins
        for i in range(len(mass_bins)-1):
            ind = np.where(np.logical_and(log_mass >= mass_bins[i], 
                                          log_mass < mass_bins[i+1]))[0]
            
            # for haloes in mass bin, randomly generate new concentration
            # from Neto conc-mass relation
            # sort old and new concentrations from min to max
            # replace with new concentrations

            logc_new = np.random.normal(loc=logc_neto_mean[i], scale=0.1,
                                        size=len(ind))

            conc_mod[ind[np.argsort(conc[ind])]] = 10**np.sort(logc_new)

        return conc_mod

    

class AbacusSnapshot(HaloCatalogue):
    """
    Abacus halo catalogue from simulation snapshot
    """
    
    def __init__(self, file_name, snapshot_redshift, 
                 cosmology=None, particles=False, A=True, B=True,
                 box_size=2000., clean=True):
        
        print("Abacus, clean=", clean)
        self.cosmology = cosmology
        self.box_size = box_size

        # read halo catalogue file  
        if particles:
            #halo_cat = CompaSOHaloCatalog(file_name, load_subsamples="AB_all")
            halo_cat = CompaSOHaloCatalog(file_name, cleaned=clean, 
                                  fields=['N', 'x_L2com', 'v_L2com', 'rvcirc_max_L2com'],
                                          subsamples=dict(A=A, B=B, rv=True))
        else:
            #halo_cat = CompaSOHaloCatalog(file_name)
            halo_cat = CompaSOHaloCatalog(file_name, cleaned=clean, 
                                  fields=['N', 'x_L2com', 'v_L2com', 'rvcirc_max_L2com'])
                
        m_par = self.__read_header(halo_cat, "ParticleMassHMsun")
        self.so_density = self.__read_header(halo_cat, "SODensityL1")
        print("SODensity:", self.so_density)
            
        self._quantities = {
            'pos':   self.__read_property(halo_cat,'x_L2com'),
            'vel':   self.__read_property(halo_cat,'v_L2com'),
            'mass':  self.__read_property(halo_cat,'N') * m_par,
            'rvmax': self.__read_property(halo_cat,'rvcirc_max_L2com')
            }
            
        if particles:
            halo_id, pos, vel, npar = self.__read_particles(halo_cat,A,B)
            self._particles = {
                'halo_id': halo_id,
                'pos' : pos,
                'vel' : vel
            }
                
            self._quantities["npar"] = npar
            pstart = np.cumsum(npar)
            pstart[1:] = pstart[:-1]
            pstart[0]=0
            self._quantities["pstart"] = pstart
            
                
        self.size = len(self._quantities['mass'][...])

        self.add("zcos", np.ones(self.size)*snapshot_redshift)
        

    def __read_particles(self, halo_cat, A=True, B=True):
        
        if A: halo_idA, posA, velA, nparA = self.__read_particles_X(halo_cat, "A")
        if B: halo_idB, posB, velB, nparB = self.__read_particles_X(halo_cat, "B")
            
        if A and not B:
            halo_id, pos, vel, npar = halo_idA, posA, velA, nparA
        elif B and not A:
            halo_id, pos, vel, npar = halo_idB, posB, velB, nparB
        elif A and B:
            halo_id = np.concatenate([halo_idA, halo_idB])
            del halo_idA, halo_idB
            idx = np.argsort(halo_id)
            halo_id = halo_id[idx]
            pos = np.concatenate([posA, posB])[idx]
            del posA, posB
            vel = np.concatenate([velA, velB])[idx]
            del velA, velB
            npar = nparA + nparB
            del idx, nparA, nparB

        # randomly shuffle particles for each halo
        x_rand = np.random.rand(len(halo_id)) + halo_id
        idx_sort = np.argsort(x_rand)
            
        return halo_id, pos[idx_sort], vel[idx_sort], npar
        
        
    def __read_particles_X(self, halo_cat, X="A"):
        npar = np.array(halo_cat.halos["npout%s"%X])
        nstart = np.array(halo_cat.halos["npstart%s"%X])

        halo_id = np.repeat(np.arange(len(npar)), npar)
        
        particle_idx = np.repeat(nstart, npar)
        
        x = np.cumsum(npar)
        x[1:] = x[:-1]
        x[0] = 0
        
        particle_idx = particle_idx + np.arange(len(particle_idx)) - np.repeat(x, npar)
        particle_idx = np.array(particle_idx, dtype=np.int64)
        
        pos = halo_cat.subsamples["pos"][particle_idx]
        vel = halo_cat.subsamples["vel"][particle_idx]        
        return halo_id, pos, vel, npar
        
    
    def get_random_particles(self, number): 
        # particles are already shuffled, so just pick first N for each halo
        # number - array with number of particles to get from each halo
        # return index of particles
        
        
        pstart = self.get("pstart")
        
        particle_idx = np.repeat(pstart, number)
        
        x = np.cumsum(number)
        x[1:] = x[:-1]
        x[0] = 0
        
        particle_idx = particle_idx + np.arange(len(particle_idx)) - np.repeat(x, number)
        particle_idx = np.array(particle_idx, dtype=np.int64)
        
        # if there are more satellites than particles, just set index to -1
        npar = self.get("npar")
        npar = np.repeat(npar, number)
        isat = np.arange(len(particle_idx)) - np.repeat(x, number) + 1
        particle_idx[npar<isat] = -1
        
        return particle_idx
      
    
    def get_particle_property(self, prop, index):
        return self._particles[prop][index]
        

    def __read_property(self, halo_cat, prop):
        # read property from halo file
        #return halo_cat["Data/%s"%prop][...]
    
        print(prop)
    
        return np.array(halo_cat.halos[prop])
    
    def __read_header(self, halo_cat, prop):
        print(prop)
        return halo_cat.header[prop]
    
    
    def __read_property_hdf5(self, halo_cat, prop):
        # read property from halo file
        return halo_cat[prop][...]
    
    def get_r200(self, comoving=True):
        """
        Returns R200mean of each halo

        Args:
            comoving: (optional) if True convert to comoving distance
        Returns:
            array of R200mean [Mpc/h]
        """
        rho_mean = self.cosmology.mean_density(self.get("zcos"))
        r200 = (3./(4*self.so_density*np.pi) * self.get("mass") / rho_mean)**(1./3)
        
        if comoving:
            return r200 * (1.+self.get("zcos"))
        else:
            return r200
        
        
        
class AbacusSnapshotUnresolved(HaloCatalogue):
    """
    Abacus catalogue of unresolved haloes, using random field particles as tracers
    """
    
    def __init__(self, file_name, snapshot_redshift, cosmology=None, box_size=2000., 
                 SODensity=200, start=0, skip=1):
        
        self.cosmology = cosmology
        self.box_size = box_size
        self.so_density = SODensity

        # read halo catalogue file  
        halo_cat = h5py.File(file_name, "r")
        self._quantities = {
            'pos':   self.__read_property_hdf5(halo_cat,'position',start,skip),
            'vel':   self.__read_property_hdf5(halo_cat,'velocity',start,skip),
            'mass':  self.__read_property_hdf5(halo_cat,'mass',start,skip)*1e10
            }
        
        self.size = len(self._quantities['mass'][...])
        self._quantities["rvmax"] = self.__get_random_rvmax(self.size)

        self.add("zcos", np.ones(self.size)*snapshot_redshift)

    def __read_property_hdf5(self, halo_cat, prop, start=0, skip=1):
        # read property from halo file
        return halo_cat[prop][...][start::skip]
    
    def get_r200(self, comoving=True):
        """
        Returns R200mean of each halo

        Args:
            comoving: (optional) if True convert to comoving distance
        Returns:
            array of R200mean [Mpc/h]
        """
        rho_mean = self.cosmology.mean_density(self.get("zcos"))
        r200 = (3./(4*self.so_density*np.pi) * self.get("mass") / rho_mean)**(1./3)
        
        if comoving:
            return r200 * (1.+self.get("zcos"))
        else:
            return r200
        
        
    def __get_random_rvmax(self, N):
        # get random values of RVmax from skew-normal distribution
        return 10**skewnorm.rvs(-1.7, loc=-1.1, scale=0.33, size=N)
        
        # get R200 of unresolved haloes
        r200 = self.get("r200")[np.invert(self.get("is_resolved"))]
        idx = np.argsort(r200)
        idx = np.argsort(idx)
        
        # generate random concentration from Gaussian
        c = np.random.normal(loc=8.5, scale=2.0, size=len(r200))
        c = np.sort(c)
        c = c[idx]
        
        # convert this to rvmax
        rvmax = 2.16 * r200 / c
        
        return rvmax
    
    
    
    