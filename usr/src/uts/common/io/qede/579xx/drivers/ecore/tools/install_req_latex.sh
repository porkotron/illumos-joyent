#!/bin/bash
#
# Install the necessary packages to enable the pdf generate script to work properly on the ecore_documentation.
# The script assumes yum is supported and was tested on Fedora.
###############################################################################################################

yum install -y texmaker
yum install -y texlive-tocbibind
yum install -y texlive-titlesec
yum install -y texlive-lipsum
yum install -y texlive-mdframed

#
# May 2016 - by Ram
# I have had no success with the above script. So here is what I did to make it work for me:
#  1) Install texmaker. Since yum experienced issues finding a libpoppler-qt4.so.14 I forced the installation
#  2) I have installed the below packages. Note that I didn't check what is the minimum required from the list
#        yum install -y texlive-latex-bin-bin
#        yum install -y texlive-bibtex-bin-bin
#        yum install -y texlive-bibtex-bin
#        yum install -y texlive-babel-english
#        yum install -y texlive-fancyhdr
#        yum install -y texlive-amscls 
#        yum install -y pandoc-pdf
#        yum install -y texlive-cm-super
#        yum install -y texlive\*fonts\*

