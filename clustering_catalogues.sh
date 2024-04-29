#BGS clustering catalogues

#Instructions for generating clustering and random catalogues for the BGS using the 
#`mkCat_main.py` script, starting from the `full_HPmapcut` catalogues produced by Ashley.

#This script can be run by doing ./clustering_catalogues.sh

#First, load the DESI environment.
source /global/common/software/desi/users/adematti/cosmodesi_environment.sh main

#Create a new directory `desi` in your scratch space, and clone the latest 
#version of the LSS repo here. Using a different directory name here is fine, 
#and none of the lines below will be affected
export LSS_DIR=$SCRATCH/desi
mkdir -p $LSS_DIR
cd $LSS_DIR
git clone https://github.com/desihub/LSS.git

#Make a directory to store the clustering and random catalogues, with the 
#right directory structure expected by `mkCat_main.py`
export OUTPUT_DIR=$LSS_DIR/main/LSS/iron/LSScats/test
mkdir -p $OUTPUT_DIR

#Copy the `full_HPmapcut` files that are needed, for data and randoms. 
#This copies 4 of the 18 random files, but a different number can be used if needed.
#v1.3 seems to be the most up to date version, which includes BITWEIGHTS
export DATA_DIR='/global/cfs/cdirs/desi/survey/catalogs/Y1/LSS/iron/LSScats/v1.3'
cp $DATA_DIR/BGS_BRIGHT_full_HPmapcut.dat.fits $OUTPUT_DIR
cp $DATA_DIR/BGS_BRIGHT_[0-3]_full_HPmapcut.ran.fits $OUTPUT_DIR
cp $DATA_DIR/BGS_BRIGHT_frac_tlobs.fits $OUTPUT_DIR

#Copy the regular `full` files without the HPmapcut
#cp $DATA_DIR/BGS_BRIGHT_full.dat.fits $OUTPUT_DIR
#cp $DATA_DIR/BGS_BRIGHT_[0-3]_full.ran.fits $OUTPUT_DIR

#The redshift limits are set in `mkCat_main.py`. Change these from the 
#default values of 0.01 < z < 0.5 to new values of -0.0033 < z < 1.0. 
#If the code is updated the exact line numbers might change
export SCRIPT_DIR=$LSS_DIR/LSS/scripts/main
sed -i '710 s/0.01/-0.0033/' $SCRIPT_DIR/mkCat_main.py
sed -i '710 s/0.5/1.0/' $SCRIPT_DIR/mkCat_main.py
sed -i '711 s/0.01/-0.0033/' $SCRIPT_DIR/mkCat_main.py
sed -i '712 s/0.5/1.0/' $SCRIPT_DIR/mkCat_main.py

#Finally, run the `mkCat_main.py` script to generate the catalogues. This will generate the 
#file `$OUTPUT_DIR/BGS_BRIGHT_clustering.dat.fits`, with similar random files.
#`--clusd y` - set to `y` to make the clustering catalogue 
#`--clusran y` - set to `y` to make the random catalogue(s)
#`--minr 0` - first random file is set to file number `0`
#`--maxr 4` - last random file is set to file number `0`. Increase this if more randoms are used
#By default it uses the `full_HPmapcut` files
#To use the `full` files instead, include (with the empty string) --use_map_veto ''
export PYTHONPATH=$LSS_DIR/LSS/py:$PYTHONPATH
python $SCRIPT_DIR/mkCat_main.py --basedir $LSS_DIR --type BGS_BRIGHT --clusd y --clusran y --minr 0 --maxr 4 --compmd altmtl #--use_map_veto ''

#The files produced contain the fluxes in different bands, but not magnitudes. 
#Run Sam's k-correction code to get rest-frame g-r colours and absolute r-band magnitudes
#This adds columns of `ABSMAG_R` and `REST_GMR_0P1`
git clone -b abacus https://github.com/amjsmith/hodpy.git
export PYTHONPATH=$LSS_DIR/hodpy:$PYTHONPATH
python $LSS_DIR/hodpy/tools/add_magnitudes_colours.py $OUTPUT_DIR/BGS_BRIGHT_clustering.dat.fits
for i in `seq 0 3`
do python $LSS_DIR/hodpy/tools/add_magnitudes_colours.py $OUTPUT_DIR/BGS_BRIGHT_${i}_clustering.ran.fits
done

#split into NGC and SGC
#the split files are needed for running the xirunpc.py script
python /global/u1/a/amjsmith/shared_code/splitGC.py $OUTPUT_DIR/BGS_BRIGHT_ .dat
for i in `seq 0 3`
do python /global/u1/a/amjsmith/shared_code/splitGC.py $OUTPUT_DIR/BGS_BRIGHT_ .ran $i
done