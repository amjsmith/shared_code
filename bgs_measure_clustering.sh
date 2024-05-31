#Get BGS clustering measurements
#First, run the bgs_clustering_catalogues.sh script to generate clustering catalogues
#for the different volume-limited samples

#Catalogue version to use. v1.4pip is latest version with PIP weights
export VERSION=v1.4pip

#Load the DESI environment.
source /global/common/software/desi/users/adematti/cosmodesi_environment.sh main

#Use the LSS code that was cloned from github when running bgs_clustering_catalogues.sh
LSS_DIR=$SCRATCH/desi
export CAT_DIR=Y1/LSS/iron/LSScats #directory structure of the LSS catalogue
export PYTHONPATH=$LSS_DIR/LSS/py:$PYTHONPATH
SCRIPT_DIR=$LSS_DIR/LSS/scripts

OUTPUT_DIR=$LSS_DIR/$CAT_DIR/$VERSION

###################################################################################
#GET CLUSTERING OF THE -21.5 COSMOLOGY SAMPLE

#Run xirunpc.py to get clustering
#`--corr_type rppi` - Correlation function type. Set to rppi for wp(rp)
#`--bin_type log` - Bin type. Set to log for logarithmic bins or lin for linear bins
#`--njack 60` - Number of jackknife regions, for jackknife errors
#`--nran 4` - Number of random files to use
#`--weight_type pip_angular_bitwise` - Type of weighting to use. For v1.4pip catalogue, use pip_angular_bitwise to use the PIP+angular weighting, redshift failure and systematic weights. If the version if v1.4, this should be set to default_angular_bitwise. 
#`--option 'ntile>1'` - Cut to regions of the footprint with a tile coverage >= this value. E.g. 'ntile>1' will use the full area, 'ntile>2' will cut to regions with NTILE>=2
#`--pimax 80` - Value of pi_max to use when calculating wp(rp)
srun -N 1 -C cpu -t 04:00:00 --qos interactive --account desi python $SCRIPT_DIR/xirunpc.py --tracer BGS_BRIGHT-21.5 --survey Y1 --verspec iron --corr_type rppi --bin_type log --njack 60 --nran 4 --basedir $OUTPUT_DIR/BGS_BRIGHT-21.5/ --outdir $OUTPUT_DIR/clustering/outdir_xirunpc_BGS_BRIGHT-21.5 --zlim 0.1 0.4 --maglim -100 -21.5 --weight_type pip_angular_bitwise --option 'ntile>1' --pimax 80


###################################################################################
#GET CLUSTERING OF VOLUME-LIMITED SAMPLES WITH DIFFERENT MAGNITUDE CUTS

#Magnitude and redshift cuts of the different samples
declare -a magnitude=(-22.0 -21.5 -21.0 -20.5 -20.0  -19.5 -19.0  -18.5   -18.0)
declare -a      zmax=(  0.3   0.3   0.3   0.3   0.25   0.2   0.15   0.125   0.1)

for m in `seq 0 8`
do 
    srun -N 1 -C cpu -t 04:00:00 --qos interactive --account desi python $SCRIPT_DIR/xirunpc.py --tracer BGS_BRIGHT-21.5 --survey Y1 --verspec iron --corr_type rppi --bin_type log --njack 60 --nran $NUM_RAND --basedir $OUTPUT_DIR/MAG${magnitude[$m]}/ --outdir $OUTPUT_DIR/clustering/outdir_xirunpc_mag${magnitude[$m]} --zlim 0.05 ${zmax[$m]} --maglim -100 ${magnitude[$m]} --weight_type pip_angular_bitwise --option 'ntile>1' --pimax 80

done
