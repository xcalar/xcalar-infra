import json
import string
import sys
import random
import datetime
import time
from datetime import date, timedelta
from faker import Faker
from faker.providers import BaseProvider

maxNum = 100000000000
symbols = ['FBIZ', 'LBRDA', 'NEBUU', 'ONVO', 'RBBN', 'AMPH', 'ENZL', 'EVFTC', 'IAMXW', 'IBKR', 'USLM', 'CAR', 'EKSO', 'EPZM', 'PDCE', 'DXCM', 'ESGE', 'SPTN', 'VRTSP', 'EHR', 'GBCI', 'SCCI', 'IRBT', 'TISA', 'AEGN', 'FTXD', 'LMAT', 'OCLR', 'TVTY', 'ATAX', 'ROBT', 'BABY', 'BATRA', 'IAC', 'SDVY', 'DWMC', 'INVE', 'ALIM', 'BYSI', 'MMDMR', 'WRLSR', 'ADXS', 'CYTX', 'FNJN', 'INAP', 'NEBUW', 'ADXSW', 'JOUT', 'OXSQ', 'PTI', 'SPKE', 'TIG', 'BRPA', 'FITB', 'LFVN', 'LSCC', 'VIDI', 'GMLP', 'OTG', 'PS', 'AMSF', 'RADA', 'ABIL', 'BCOR', 'ELSE', 'KURA', 'OTIC', 'VRAY', 'ADMA', 'RARX', 'ROST', 'SREV', 'AEIS', 'BOKFL', 'CGVIC', 'CHRS', 'EVBG', 'FTAG', 'CRAI', 'MPVD', 'DVAX', 'AAME', 'AERI', 'APPN', 'DDBI', 'FKLY', 'BMCH', 'DUSA', 'ITEQ', 'PSET', 'EVFM', 'IBTX', 'BBH', 'ENG', 'AGFS', 'GAINN', 'OVID', 'SRET', 'KTOVW', 'OCFC', 'SILC', 'CDL', 'VEON', 'HEBT', 'OSTK', 'SPAR', 'NESR', 'CHFC', 'PSC', 'UONE', 'OBLN', 'PDCO', 'CENTA', 'IGLE', 'IMV', 'QIWI', 'APEN', 'MINDP', 'PYPL', 'RBCAA', 'RTTR', 'WTFCW', 'XRAY', 'CDMO', 'FENC', 'GLDD', 'MDXG', 'TWOU', 'DDOC', 'SMPL', 'ALRN', 'ATACR', 'CARB', 'CNCE', 'EQFN', 'GABC', 'SIMO', 'ICLN', 'ICON', 'SCON', 'CDNA', 'KELYB', 'MOGLC', 'WRLS', 'BNTCW', 'CYTR', 'ISTB', 'MPACU', 'RAVE', 'APOG', 'LMFAW', 'SOCL', 'ITRN', 'SPEX', 'ACOR', 'CREG', 'COOL', 'EVLMC', 'IIIV', 'LMRK', 'RILYZ', 'WASH', 'ARQL', 'ASMB', 'EACQ', 'GNTY', 'IOVA', 'LALT', 'MRCY', 'ACSF', 'FMBI', 'VKTXW', 'ASTC', 'COCP', 'PBSK', 'PCTI', 'RDIB', 'IRIX', 'SNDX', 'HELE', 'JSYNU', 'MPACW', 'OTEX', 'SHLO', 'BPOPN', 'HMSY', 'ICCH', 'ORBC', 'ADOM', 'JNP', 'RPD', 'NTRS', 'CREE', 'EFSC', 'OPGN', 'PFIS', 'RING', 'ZIONW', 'ALGRU', 'DCOM', 'DOGZ', 'INTX', 'LULU', 'REFR', 'REGN', 'BLFS', 'MPAC', 'SBGI', 'WOOD', 'DSKEW', 'GLNG', 'NBEV', 'SRRA', 'FBSS', 'IFGL', 'MBB', 'WB', 'POWL', 'APPF', 'DWTR', 'RCKT', 'TRTL', 'VCTR', 'AMWD', 'CSWI', 'DFFN', 'FINX', 'FUV', 'JSYNW', 'PCRX', 'SHLM', 'CVLY', 'MBUU', 'NATI', 'VEACU', 'BCLI', 'CBLI', 'CRON', 'ENTX', 'ESTRW', 'LAZY', 'TWIN', 'ACGLP', 'DCIX', 'SFNC', 'CNTY', 'CTXS', 'DTUS', 'WTFCM', 'AROW', 'BBP', 'RGLD', 'AXSM', 'DYNT', 'MPAA', 'MTEC', 'RETO', 'YY', 'FONR', 'GFN', 'BOLT', 'TCPC', 'BOFI', 'FANH', 'ASRV', 'WHLRW', 'BLKB', 'VEACW', 'CBLK', 'DWSN', 'EDRY', 'GTXI', 'LEDS', 'HONE', 'ICHR', 'OHRP', 'TQQQ', 'GPIC', 'RFIL', 'WEN', 'ABEOW', 'EAST', 'IFMK', 'NURO', 'PLCE', 'PPC', 'ZFGN', 'QDEL', 'ASTE', 'BANFP', 'ALPN', 'DHIL', 'FSACW', 'MSVB', 'AHPAW', 'SIVB', 'ACWI', 'DWSH', 'ESGU', 'ETSY', 'RIGL', 'SALM', 'CLDX', 'FRSH', 'IVAC', 'MASI', 'MRSN', 'SAEX', 'DGLY', 'IIIN', 'OFLX', 'ADMS', 'ICFI', 'FWP', 'OFS', 'POPE', 'SRRK', 'FFNW', 'ISIG', 'MGIC', 'MTFBW', 'CPTAG', 'PDEX', 'HYXE', 'ICUI', 'KTOV', 'CELH', 'FSACU', 'IIVI', 'AHPAU', 'EVOL', 'FWONA', 'ORBK', 'ARTNA', 'CYHHZ', 'JRJC', 'APTX', 'AREX', 'EXAS', 'CIBR', 'CLWT', 'WEB', 'CERCW', 'DOTA', 'JBLU', 'JYNT', 'ASML', 'NVMI', 'SFM', 'HJLI', 'IVTY', 'VNOM', 'LDRI', 'VMBS', 'AQB', 'EVGBC', 'GBLI', 'MIK', 'QQQX', 'VOXX', 'JSYN', 'SLVO', 'TRVG', 'FEYE', 'OBSV', 'CWST', 'SAMG', 'SHLDW', 'UBNK', 'CCCL', 'CCRN', 'MNST', 'NEPT', 'WHLR', 'ALTY', 'DAKT', 'INBK', 'LOB', 'MARK', 'NRIM', 'AVAV', 'THST', 'HMTV', 'SIRI', 'SUMR', 'EDGW', 'MMAC', 'MOTS', 'PLSE', 'CCNE', 'FNLC', 'FUSB', 'MCBC', 'CLIR', 'DOCU', 'CORI', 'GBLK', 'PLW', 'PME', 'CSWC', 'CXSE', 'FEIM', 'PFF', 'AMR', 'DMRC', 'MRIC', 'ASND', 'AVT', 'PEGI', 'BLMT', 'CRUS', 'CFMS', 'FLIR', 'HEAR', 'INTL', 'WVVIP', 'JASNW', 'MYGN', 'QCOM', 'RETA', 'AKRX', 'AMTD', 'NVMM', 'PHII', 'PTNR', 'SCPH', 'WNFM', 'BCRX', 'FIXD', 'MYOS', 'TECD', 'FNSR', 'LOPE', 'NFBK', 'PBCT', 'SOHO', 'ACHN', 'GTLS', 'MACQW', 'MAGS', 'PLAY', 'CCXI', 'ERII', 'FWONK', 'TCDA', 'VGSH', 'EZPW', 'LSTR', 'NVIV', 'VALX', 'YIN', 'NSEC', 'TSEM', 'ABAX', 'AKER', 'EIGI', 'GSBC', 'GWRS', 'MOXC', 'PGTI', 'TTEC', 'CUE', 'STCN', 'CART', 'DXLG', 'VYGR', 'CDNS', 'CORE', 'MACQU', 'NBN', 'COLB', 'BPFH', 'FDEF', 'FSZ', 'EGLT', 'SMSI', 'AWRE', 'GTHX', 'AIMC', 'AMCA', 'INDB', 'AGIO', 'ALJJ', 'KBWP', 'MTEM', 'ORPN', 'UXIN', 'CARV', 'ILPT', 'MXWL', 'PLBC', 'ACST', 'CHDN', 'HSKA', 'ICLR', 'ISNS', 'KRYS', 'NOVN', 'TECH', 'EACQW', 'MBSD', 'VREX', 'FITBI', 'MDLZ', 'RFDI', 'SPRO', 'VTGN', 'AAPL', 'DEST', 'IVENC', 'AZPN', 'BIIB', 'ERIE', 'PRGX', 'VETS', 'LKOR', 'HFBC', 'NTRA', 'SMBK', 'ZIXI', 'IUSG', 'CBAK', 'KBWR', 'LCUT', 'PLXS', 'STX', 'BOLD', 'GOVNI', 'IGF', 'LEVL', 'NETE', 'SELB', 'EACQU', 'LXRX', 'MGYR', 'NGHC', 'TRMB', 'ADAP', 'AXAS', 'NNDM', 'SHY', 'USOI', 'ERI', 'IDSA', 'AVGR', 'FSV', 'MICT', 'CETXP', 'DWAS', 'GBT', 'NSSC', 'PEGA', 'SRVA', 'TOPS', 'VCYT', 'MARA', 'AMBC', 'CEVA', 'CLNE', 'FAAR', 'FNGN', 'PXS', 'CARZ', 'EASTW', 'ON', 'ALQA', 'IRTC', 'LTRPA', 'NAII', 'GECCM', 'KAAC', 'LQDT', 'ALGN', 'YGYI', 'BWB', 'CODX', 'TAOP', 'TPIC', 'DWIN', 'FEM', 'WATT', 'DRIV', 'SKYW', 'BSET', 'CPTA', 'DWAQ', 'GFED', 'HAS', 'MSON', 'CRVS', 'CTIC', 'FRSX', 'FUND', 'IBB', 'PRPL', 'STIM', 'TTEK', 'TZOO', 'AMBA', 'EOLS', 'FIBK', 'IRMD', 'BIDU', 'COBZ', 'TGEN', 'CCNI', 'NOVT', 'SELF', 'TERP', 'ARCT', 'HALL', 'MANH', 'NDLS', 'CIFS', 'AEMD', 'AGEN', 'BANF', 'HAFC', 'LGIH', 'ERIC', 'HYACW', 'BIOS', 'CALL', 'GLUU', 'SIFY', 'CSX', 'ITCI', 'HIHO', 'ORIG', 'PRAH', 'PRQR', 'SABR', 'LFAC', 'YORW', 'CTRL', 'JACK', 'EDGE', 'MATW', 'MINI', 'RNSC', 'BGFV', 'PRN', 'ACBI', 'BMTC', 'DWLD', 'LECO', 'LSXMB', 'NBCP', 'TRMD', 'MBFIO', 'TBK', 'VTVT', 'APVO', 'BAND', 'TDACU', 'COLL', 'HYACU', 'KIDS', 'MNKD', 'SKYS', 'EDBI', 'NTRI', 'PNBK', 'SMBC', 'VBND', 'BWINA', 'NXEOW', 'PDVW', 'PRAN', 'PRPH', 'TLT', 'BCPC', 'CBPO', 'CUI', 'DJCO', 'GENY', 'MIDD', 'BPFHW', 'CTRN', 'EHTH', 'FCNCA', 'III', 'NEON', 'PSAU', 'TURN', 'CDTX', 'AKAM', 'CMCSA', 'SFST', 'BHACW', 'FOXF', 'LFUS', 'NGHCO', 'NTNX', 'RMR', 'ALGT', 'FDIV', 'IDLB', 'SLIM', 'BL', 'SBUX', 'TDACW', 'AUPH', 'IDCC', 'IDSY', 'RKDA', 'FTGC', 'MOBL', 'RMBS', 'UAE', 'VSTM', 'ALCO', 'MGEE', 'NXEOU', 'OXBRW', 'BWEN', 'CMFN', 'MITL', 'RYAAY', 'TLND', 'CTRP', 'KBWD', 'KNSL', 'BOTZ', 'MOTA', 'SOXX', 'WABC', 'WILC', 'AKAO', 'AOBC', 'PCH', 'BHACU', 'DTYL', 'EA', 'EGAN', 'GNCA', 'MBCN', 'TA', 'UG', 'TRUE', 'TYPE', 'EVLV', 'SBSI', 'TTGT', 'LTBR', 'CCD', 'CSB', 'RNDM', 'TTMI', 'CATC', 'RDFN', 'SHIP', 'GENE', 'SNHNL', 'EMCF', 'NWPX', 'MIME', 'ESSA', 'SUPN', 'TUES', 'UVSP', 'WYNN', 'CAPR', 'FTCS', 'CFRX', 'HCCI', 'NAOV', 'SLNO', 'SNOAW', 'ECHO', 'FFWM', 'KBLMW', 'MAPI', 'PETZ', 'NTGN', 'SATS', 'HSON', 'LMRKP', 'TROV', 'CWBC', 'MBWM', 'YDIV', 'ASYS', 'CYCC', 'EGC', 'FSCT', 'IEUS', 'PKOH', 'SPWR', 'UMRX', 'BASI', 'MELR', 'PNTR', 'ZGNX', 'OVAS', 'INDUU', 'IVFVC', 'KINS', 'LUNG', 'GWGH', 'LIVE', 'NYNY', 'SRCL', 'ARCB', 'BHBK', 'LPSN', 'ZUMZ', 'BLNKW', 'HEWG', 'TIVO', 'VCEL', 'AQMS', 'KBLMU', 'PETX', 'CHEKW', 'DRRX', 'MLHR', 'SMED', 'AMAT', 'AMD', 'LACQW', 'NVFY', 'UNAM', 'AMRWW', 'CSF', 'CWCO', 'FDUS', 'PSCT', 'BLMN', 'EYEN', 'CNET', 'COHU', 'HYGS', 'LPTH', 'VC', 'CHMA', 'CTRV', 'EMCB', 'KBWB', 'OBAS', 'SBOT', 'TCRD', 'BKCC', 'DFBH', 'INDUW', 'LUNA', 'LX', 'WSBF', 'EMMS', 'PBIO', 'FTR', 'IOTS', 'QNST', 'BURG', 'SOHU', 'CPRX', 'HCAPZ', 'WPRT', 'CEMI', 'CMRX', 'DLPN', 'DXJS', 'SENEB', 'SSB', 'CONE', 'FCVT', 'LACQU', 'PGNX', 'SKYY', 'SODA', 'YLDE', 'KTCC', 'MESO', 'SSNC', 'CADC', 'CATM', 'BVSN', 'CBAY', 'EGRX', 'GENC', 'NFTY', 'PENN', 'PTIE', 'CGIX', 'MTECU', 'TACT', 'AMKR', 'MNGA', 'OFIX', 'PDLI', 'SCWX', 'SSYS', 'CLAR', 'MYOK', 'PRMW', 'QSII', 'SQLV', 'ELOX', 'IMPV', 'ROSEW', 'ZEAL', 'BCBP', 'NUROW', 'ACHV', 'CIVB', 'FORK', 'SAFT', 'SNBR', 'UGLD', 'AFHBL', 'BFRA', 'BRKR', 'HBCP', 'WSFS', 'CLBK', 'MGLN', 'CSJ', 'FBIOP', 'HX', 'NXTDW', 'FYC', 'GTYHW', 'AABA', 'CCLP', 'FFIN', 'FLXN', 'ACRX', 'MTECW', 'PIE', 'RUSHB', 'VBLT', 'ZAGG', 'CHTR', 'GROW', 'LOXO', 'BPRN', 'FCEF', 'JCS', 'KZIA', 'QADA', 'ROSEU', 'BNFT', 'CMTA', 'MARPS', 'PEBO', 'CPRT', 'FORM', 'SLMBP', 'ZYNE', 'EGOV', 'FALN', 'IEAWW', 'IPWR', 'ARLP', 'BIOC', 'ITI', 'MSTR', 'PUI', 'SIFI', 'MVBF', 'RBIO', 'SGYP', 'TCBIP', 'GTYHU', 'RPIBC', 'CHMG', 'GOGO', 'IFRX', 'AMTX', 'EXEL', 'FEMS', 'HLNE', 'MNTA', 'NIHD', 'UNB', 'HURC', 'SLGN', 'AAWW', 'COKE', 'GLPI', 'QYLD', 'TRMT', 'FMI', 'FTLB', 'IPAS', 'WIN', 'BRPAR', 'CERC', 'LRAD', 'TIPT', 'ALT', 'GLRE', 'EEMA', 'FISV', 'ICAD', 'VRSK', 'FHK', 'SYRS', 'ZIOP', 'GEOS', 'GRIN', 'SLP', 'OSPRU', 'PXI', 'NEWTI', 'PAVMZ', 'QUMU', 'WSTL', 'ACXM', 'PNNT', 'SLGL', 'DORM', 'DWLV', 'ESND', 'MANT', 'MREO', 'TBPH', 'CTWS', 'HCSG', 'JBHT', 'MRVL', 'PEBK', 'ANDE', 'BANR', 'DXPE', 'EAGL', 'FMK', 'AAOI', 'CLRBW', 'MGI', 'VWOB', 'LASR', 'ISCA', 'KIN', 'LSBK', 'TCBIL', 'HIIQ', 'KNDI', 'PCOM', 'TLF', 'EXPI', 'MSG', 'SBNYW', 'BRACU', 'OSPRW', 'PIO', 'SPNE', 'BOTJ', 'MYL', 'XPER', 'BDSI', 'DSLV', 'NUAN', 'SLDB', 'FCEL', 'GULF', 'PCSB', 'SPHS', 'ARRY', 'HBIO', 'OTTW', 'HDSN', 'MDSO', 'CMCT', 'CYRX', 'GECC', 'SAUC', 'UFPI', 'UMPQ', 'VTHR', 'ARLZ', 'CKPT', 'LTRX', 'YTEN', 'VIRC', 'VSDA', 'ZNGA', 'BDGE', 'CATS', 'GLIBP', 'NCNA', 'MDGL', 'MKTX', 'BRACW', 'DENN', 'HOLI', 'IIJI', 'CNACU', 'NDRAW', 'TWNK', 'CME', 'OSS', 'PFLT', 'TIBRW', 'AEZS', 'SFBC', 'ASUR', 'MAR', 'PRFT', 'STDY', 'BOXL', 'ULH', 'CIDM', 'ENDP', 'LMNR', 'MSFT', 'WSC', 'BTEC', 'CZWI', 'ISSC', 'SES', 'AGFSW', 'AGNCN', 'AKBA', 'VXRT', 'ANIP', 'AXTI', 'BRID', 'NEWT', 'FRPT', 'IART', 'CNACW', 'MGRC', 'FNTEW', 'QRTEA', 'SAVE', 'STRT', 'TIBRU', 'CASH', 'FTD', 'UNTY', 'EFOI', 'IGOV', 'IONS', 'PEZ', 'PINC', 'PRFZ', 'IBKCP', 'MFNC', 'SMMT', 'VOD', 'JTPY', 'ONEQ', 'TMCX', 'AMRB', 'CGEN', 'OSPN', 'JASN', 'MERC', 'PSCD', 'RDNT', 'RDVT', 'UTMD', 'AUTO', 'EXPO', 'GRIF', 'HCM', 'LPTX', 'LORL', 'NVEC', 'NXTM', 'APRI', 'FNY', 'GNMX', 'HYND', 'VGIT', 'EBSB', 'FNTEU', 'LCA', 'SUSB', 'GLPG', 'HWC', 'HYAC', 'BCACW', 'DFNL', 'IEP', 'NXPI', 'ORLY', 'SQBG', 'GAIN', 'LEXEA', 'MMLP', 'BRKL', 'CIU', 'NTGR', 'GIII', 'IMTE', 'MKGI', 'NTIC', 'BRAC', 'CTSO', 'ISBC', 'PSCF', 'RNWK', 'XT', 'AGNCB', 'GOODM', 'GRID', 'MYND', 'VCIT', 'CRTO', 'NVEE', 'ADRU', 'PAGG', 'ELGX', 'OPHC', 'CNAC', 'HRTX', 'BCACU', 'MAT', 'MOMO', 'TWLVU', 'AIRG', 'BANX', 'BLPH', 'HPJ', 'FOANC', 'SSP', 'CBRL', 'CPLA', 'IBEX', 'LMNX', 'POLA', 'ENFC', 'FWRD', 'ESGRP', 'GOODO', 'CFFN', 'VIIZ', 'AIQ', 'FSTR', 'LOAN', 'MSBF', 'NVDA', 'XOG', 'LINK', 'PBBI', 'LBC', 'BIS', 'DOTAW', 'NMRK', 'PAYX', 'ARRS', 'IBCP', 'OXSQL', 'SGEN', 'HPT', 'PACQ', 'GCBC', 'IBUY', 'XLNX', 'AVID', 'CATY', 'TRIP', 'ZION', 'CYAD', 'EGBN', 'EXPE', 'SONC', 'VIIX', 'ACMR', 'SLRC', 'XBIT', 'XNCR', 'CBOE', 'FELE', 'WCFB', 'KAACU', 'DOTAU', 'EXLS', 'FMAX', 'NTWK', 'UTSI', 'IMNP', 'IPIC', 'VRTU', 'DVCR', 'LPNT', 'PACW', 'CERS', 'JCOM', 'KOPN', 'LGND', 'CHKP', 'ACT', 'JKHY', 'SPWH', 'UBSI', 'LGCYP', 'SONA', 'ARPO', 'OVBC', 'RVSB', 'SPNS', 'SSBI', 'ADRO', 'SIR', 'TITN', 'DAX', 'KAACW', 'SBFG', 'ELON', 'FDT', 'BELFA', 'GSUM', 'GSVC', 'PEP', 'QTNA', 'VRTS', 'AVDL', 'CPSH', 'HAIR', 'VECO', 'WERN', 'WIX', 'BLCM', 'AMRH', 'CSGS', 'CYTXZ', 'RUTH', 'TANH', 'ICPT', 'BVXVW', 'MFINL', 'PIHPP', 'PRPLW', 'TRIL', 'MDWD', 'BHF', 'FTSL', 'LYL', 'ASRVP', 'CLXT', 'SMIT', 'RUN', 'BOOM', 'CBTX', 'AGZD', 'BWFG', 'CHSCL', 'CLCT', 'MTSL', 'FLNT', 'KFRC', 'SPCB', 'UCFC', 'CMCTP', 'HBANN', 'IMI', 'TANNI', 'TXRH', 'AMRN', 'CLBS', 'CMSSW', 'CSPI', 'FRED', 'LMRKN', 'NUVA', 'OSPR', 'RTIX', 'AUBN', 'AZRX', 'HGSH', 'MPCT', 'PSCH', 'SCKT', 'MUDSW', 'NWFL', 'APDN', 'BOJA', 'FFIV', 'APDNW', 'BJRI', 'FCCY', 'FCSC', 'JJSF', 'PBCTP', 'TAST', 'LINC', 'VONE', 'HIMX', 'SAIA', 'DLBS', 'SFBS', 'SMTC', 'CHSCN', 'HSII', 'PPIH', 'CNXN', 'IMRN', 'NCMI', 'ARTX', 'BPOP', 'PSEC', 'SNGXW', 'CMSSU', 'DCPH', 'SKIS', 'ADUS', 'BNDX', 'CLIRW', 'IRDMB', 'KCAPL', 'LILA', 'BCNA', 'MUDSU', 'ONS', 'ATRO', 'GOOG', 'NSTG', 'PFBI', 'CSSE', 'WAFDW', 'XLRN', 'IZEA', 'KMDA', 'MTGEP', 'VONG', 'XGTIW', 'DYSL', 'FLN', 'OPK', 'USAP', 'AGRX', 'NBRV', 'RDCM', 'BBRX', 'CINF', 'GRNQ', 'MCRI', 'MPB', 'CAC', 'OLLI', 'QRVO', 'CVCY', 'RXII', 'SGOC', 'CYRXW', 'RNLC', 'PGJ', 'FRME', 'OTIV', 'USCR', 'VIAV', 'ATAI', 'CJJD', 'CYAN', 'OCSI', 'VRNS', 'AGND', 'FCBC', 'MNLO', 'DLTR', 'DXGE', 'ESIO', 'OSBC', 'AGTC', 'ETFC', 'FLL', 'OHGI', 'BBBY', 'BMLP', 'EDUC', 'GASS', 'SPKEP', 'AGMH', 'CYOU', 'PDP', 'SMMF', 'CYRN', 'HUNTU', 'VTIP', 'DFVL', 'USMC', 'BOCH', 'FGBI', 'GLBZ', 'NNBR', 'SYMC', 'TTD', 'KEQU', 'MBIN', 'PFPT', 'ROSE', 'SNPS', 'CSCO', 'CXDC', 'EFBI', 'FLKS', 'FRPH', 'HTBX', 'LLEX', 'RILY', 'ADRE', 'FNK', 'RGNX', 'ROLL', 'BGNE', 'ENPH', 'OIIM', 'USAT', 'BECN', 'ABMD', 'CAAS', 'DGICB', 'HSIC', 'IEF', 'VICR', 'HUNTW', 'ILG', 'PMOM', 'SCACW', 'EQRR', 'FBZ', 'SVRA', 'IMKTA', 'ONSIW', 'UPL', 'KALA', 'NHTC', 'NLNK', 'TRIB', 'ATRI', 'CHEK', 'HDS', 'LCNB', 'PFBC', 'RILYG', 'SEIC', 'AIA', 'GFNSL', 'HNRG', 'SBPH', 'SGRP', 'INFN', 'KLXI', 'ONTXW', 'CTMX', 'CGBD', 'CPHC', 'FAMI', 'LNGR', 'NTEC', 'KBLM', 'MTCH', 'WVFC', 'KANG', 'REIS', 'SSLJ', 'TCX', 'MFIN', 'OVLY', 'SCACU', 'DCAR', 'HOPE', 'SOHOB', 'XELA', 'DSWL', 'TCCO', 'FTHI', 'KHC', 'ASLN', 'ATAC', 'NAKD', 'FCCO', 'MACK', 'TAPR', 'XENE', 'ADRA', 'DGRE', 'CSTR', 'LYTS', 'STRL', 'ATNI', 'DNBF', 'SNDE', 'CLRB', 'CLSN', 'FIVN', 'AETI', 'LBTYK', 'PZZA', 'RBB', 'TBRGU', 'HTLF', 'MEIP', 'PSDO', 'ABTX', 'NWLI', 'TCBK', 'VTL', 'APOPW', 'BCOM', 'NK', 'CLVS', 'HBNC', 'ABCB', 'DISH', 'FONE', 'VIGI', 'CDC', 'CEY', 'INGN', 'SNMX', 'VSAT', 'OASM', 'TCON', 'ULTA', 'USATP', 'WRLD', 'ATOM', 'KRNY', 'SYNA', 'THFF', 'BMRC', 'CSML', 'MBRX', 'ZG', 'HTLD', 'IMMU', 'MCHX', 'RTRX', 'ADI', 'BLRX', 'PICO', 'ASFI', 'CNTF', 'FDTS', 'TCBI', 'BNSO', 'CIVEC', 'FLAT', 'FTXO', 'HYLS', 'ATRC', 'BFIT', 'SEII', 'EEI', 'DLTH', 'PACQW', 'PVBC', 'SND', 'CRUSC', 'PPBI', 'AMED', 'LAND', 'SPI', 'WLFC', 'IAMXR', 'SYNC', 'BMRA', 'CSWCL', 'IRCP', 'XCRA', 'CIGI', 'SNSS', 'TCMD', 'POLY', 'VIAB', 'ATRA', 'DWFI', 'IDXX', 'LNTH', 'ROBO', 'TSCO', 'CPIX', 'GT', 'MDB', 'NYMTN', 'PCMI', 'STKS', 'XSPL', 'CVON', 'HCCHU', 'LOGI', 'PACQU', 'PNFP', 'YTRA', 'DISCB', 'MMDMU', 'ADIL', 'EXTR', 'HMHC', 'IDTI', 'RAVN', 'TMCXU', 'CPST', 'LBTYA', 'MLAB', 'RVNC', 'VICL', 'CGNX', 'CVCO', 'DSPG', 'IMMY', 'LANDP', 'TEDU', 'TSC', 'AKTX', 'BKNG', 'LOCO', 'PFIN', 'BBC', 'FNWB', 'HOFT', 'NHLDW', 'FSLR', 'OCSLL', 'SMCI', 'TSBK', 'VRNA', 'ABCD', 'AWSM', 'CACG', 'CLFD', 'CNCR', 'NYMTP', 'ASCMA', 'KLIC', 'MTLS', 'VSAR', 'ARKR', 'GBNK', 'HIBB', 'ITUS', 'MMDMW', 'AMEH', 'CBFV', 'LRGE', 'RCKY', 'TTWO', 'TMCXW', 'BNTC', 'ESLT', 'HMST', 'KE', 'ACWX', 'CYBR', 'DVY', 'ESGD', 'PNK', 'ACGLO', 'ARDM', 'FLWS', 'FTNT', 'MGTA', 'QCRH', 'AMSC', 'HOMB', 'HWBK', 'QTRX', 'DOVA', 'KALU', 'MEET', 'RNET', 'RARE', 'SGC', 'XGTI', 'HMNY', 'CDK', 'DGRS', 'LOGM', 'ALZH', 'DBX', 'ULTI', 'SFIX', 'CHFN', 'CLSD', 'DAIO', 'PTF', 'GSHD', 'ICCC', 'ISRL', 'MCHP', 'TSG', 'FKU', 'PIRS', 'IDRA', 'SESN', 'ECOL', 'FTXG', 'KWEB', 'LION', 'STAF', 'ESRX', 'RCII', 'ROCK', 'TMDI', 'CACC', 'NCSM', 'RMGN', 'CTG', 'ICLK', 'MEOH', 'PRTK', 'SCYX', 'WRLSU', 'BPMC', 'COST', 'EYESW', 'FMHI', 'KZR', 'ANY', 'EIDX', 'EVSTC', 'IFV', 'PFMT', 'PTH', 'SHLD', 'TCFC', 'VLGEA', 'SNFCA', 'APEI', 'APTI', 'ASNS', 'BOKF', 'COUP', 'OFED', 'FRBK', 'GLADN', 'ABIO', 'ECOR', 'GLDI', 'CUBA', 'CARA', 'FTSV', 'FVE', 'RDWR', 'DGRW', 'PVAC', 'WRLSW', 'NTES', 'BSPM', 'IESC', 'NKTR', 'NVCR', 'BSRR', 'COMM', 'HAIN', 'HWKN', 'KOOL', 'ADVM', 'CHI', 'FSBW', 'ATIS', 'SMPLW', 'VRA', 'WEYS', 'FARO', 'GAINO', 'ALSK', 'PPH', 'ZLAB', 'ADSK', 'PRTO', 'QQXT', 'SNH', 'TESS', 'GLYC', 'SPSC', 'APWC', 'ATOS', 'DIOD', 'GRVY', 'OMAB', 'ZSAN', 'CHSCP', 'EQBK', 'GWPH', 'PSL', 'WHLRP', 'CCIH', 'CVLT', 'ATVI', 'IGLD', 'KBSF', 'NERV', 'PETZC', 'PWOD', 'USEG', 'CCRC', 'MNRO', 'ASPU', 'ATISW', 'COWNZ', 'AIMT', 'IQ', 'MSEX', 'ATSG', 'EYEGW', 'FARM', 'GAINM', 'MTEX', 'NWSA', 'BYFC', 'GNTX', 'ATHN', 'FMBH', 'INFR', 'PRTA', 'SBNY', 'SGLBW', 'BREW', 'FANG', 'FLDM', 'MB', 'STLRU', 'CSFL', 'BPOPM', 'GNBC', 'ATEC', 'AVGO', 'DRIO', 'ESGR', 'GPP', 'APTO', 'EGLE', 'VBIV', 'ASPS', 'FRBA', 'ONCE', 'FAB', 'NDAQ', 'ATRS', 'SRCLP', 'SRTS', 'ALRM', 'ATACU', 'CARG', 'FVC', 'INNT', 'NKSH', 'CLPS', 'MMYT', 'KELYA', 'QBAK', 'STBZ', 'VXUS', 'STLRW', 'TGTX', 'ACIU', 'UPLD', 'USLB', 'FEP', 'FNCB', 'MORN', 'NATH', 'PFI', 'DRYS', 'GNPX', 'ITRM', 'NBIX', 'VYMI', 'GEC', 'PCYG', 'CRED', 'CTXR', 'IUSV', 'FAD', 'LENS', 'REGI', 'SPOK', 'HMTA', 'CLGN', 'EVK', 'MACQ', 'CDW', 'GVP', 'CRIS', 'ACIW', 'MRNS', 'SLAB', 'TRVN', 'PXUS', 'VCLT', 'ZS', 'HZNP', 'NTRP', 'ODT', 'SP', 'CMPR', 'CTXRW', 'HLIT', 'HWCPL', 'ONCY', 'SBAC', 'YRCW', 'BBGI', 'ARII', 'ARAY', 'LIFE', 'LMBS', 'OCUL', 'PBYI', 'ESPR', 'GNRX', 'JKI', 'MKSI', 'MRTX', 'POWI', 'CYTK', 'GERN', 'JAGX', 'OFSSL', 'VTWG', 'IBKC', 'VSMV', 'PFM', 'UNFI', 'AFMD', 'BCML', 'HFWA', 'ITRI', 'TRS', 'TTOO', 'AEY', 'ESEA', 'IMRNW', 'NTAP', 'TBIO', 'DSGX', 'QTRH', 'ANAB', 'INTU', 'INWK', 'JRVR', 'VBTX', 'RNST', 'TWNKW', 'WNEB', 'DOMO', 'LKQ', 'BICK', 'HJLIW', 'NVUS', 'WVE', 'PAAS', 'DHXM', 'JSYNR', 'PLAB', 'QLYS', 'TVIZ', 'XONE', 'EVLO', 'GSHT', 'ASNA', 'CCBG', 'ODP', 'ARWR', 'SYBX', 'AMCX', 'BKEPP', 'SOFO', 'KBWY', 'CARO', 'HUBG', 'SAL', 'VVUS', 'ATHX', 'NYMX', 'OSUR', 'CFBK', 'CY', 'FRTA', 'PTX', 'TVIX', 'APOP', 'EVOK', 'FEX', 'FTEO', 'ICBK', 'MUDS', 'NAUH', 'FATE', 'FCFS', 'FFBW', 'EDAP', 'EYE', 'GLMD', 'PCYO', 'RGEN', 'WHLM', 'CECE', 'FFHL', 'KEYW', 'SBRA', 'LAUR', 'ADMP', 'BFIN', 'IMOS', 'MOFG', 'OMED', 'ORGS', 'VTSI', 'AMDA', 'OLBK', 'OXFD', 'CRBP', 'GARS', 'IRWD', 'PHIIK', 'ACCP', 'CFBI', 'FBIO', 'KTOS', 'PMD', 'BFST', 'FPRX', 'PFG', 'EFII', 'TRHC', 'CRMT', 'HBMD', 'HYZD', 'SMRT', 'CHY', 'ORIT', 'ENT', 'SNOA', 'SPLK', 'MTFB', 'OPNT', 'SIEN', 'CDTI', 'CNSL', 'SGBX', 'CRSP', 'NFEC', 'NYMT', 'VLRX', 'DTYS', 'PERI', 'RLM', 'RMNI', 'SHBI', 'TRMK', 'KONA', 'VTWO', 'CELC', 'FORR', 'SAFM', 'SCSC', 'SKOR', 'TXN', 'USLV', 'WAFD', 'ERYP', 'FTEK', 'PRGS', 'TXMD', 'ZKIN', 'MOR', 'ELTK', 'FKO', 'GURE', 'LLNW', 'NCOM', 'VEAC', 'CHW', 'IUSB', 'ONCS', 'ZIONZ', 'CZR', 'BNCL', 'WWR', 'DAVE', 'DFRG', 'MIND', 'AOSL', 'CPTAL', 'MRTN', 'TOCA', 'NDSN', 'STMP', 'TSCAP', 'CBSH', 'CLMT', 'HIFS', 'QGEN', 'YRIV', 'CSQ', 'GYRO', 'HBP', 'CECO', 'CUTR', 'FSBC', 'NITE', 'STND', 'ANAT', 'WBA', 'CTBI', 'DMLP', 'METC', 'CMFNL', 'MCEF', 'PRTS', 'VTNR', 'BUSE', 'SPPI', 'BTAI', 'CBMG', 'KONE', 'QQQC', 'CA', 'CELG', 'FMNB', 'JBSS', 'LILAK', 'WHLRD', 'ATLO', 'BBSI', 'OKDCC', 'UFPT', 'IPHS', 'MRIN', 'RVLT', 'UNIT', 'FEUZ', 'FFKT', 'PRAA', 'SLCT', 'AQXP', 'CIVBP', 'DGLD', 'FAT', 'FLXS', 'ITIC', 'PBPB', 'CTRE', 'PATK', 'EGHT', 'NVLN', 'NWS', 'TNAV', 'UCBA', 'AVRO', 'FOX', 'MYRG', 'CG', 'KGJI', 'NCTY', 'STML', 'TDAC', 'ACAD', 'OLD', 'RCM', 'STFC', 'TYME', 'VALU', 'DWAT', 'EPAY', 'GALT', 'QUIK', 'SSNT', 'ALTR', 'COWNL', 'CRVL', 'JMU', 'NICE', 'SYBT', 'INTG', 'OXLC', 'ALKS', 'CZFC', 'OXLCO', 'PATI', 'TUSA', 'VNQI', 'AKCA', 'DFBG', 'KLAC', 'LINDW', 'LIVX', 'LTRPB', 'QABA', 'ARCW', 'ECPG', 'EMITF', 'PTGX', 'SHV', 'VNDA', 'WETF', 'ACIA', 'AFH', 'AFSI', 'DLPNW', 'FRGI', 'JNCE', 'RBCN', 'SBT', 'BEAT', 'CMCO', 'SECO', 'OPRX', 'PTCT', 'SUNS', 'CDXC', 'GEVO', 'RNDV', 'TACOW', 'ACLS', 'HABT', 'MGEN', 'NXEO', 'RGLS', 'YLCO', 'ACER', 'CAKE', 'IIN', 'OXLCM', 'PLXP', 'PRKR', 'INBKL', 'REDU', 'AVEO', 'CVV', 'DRNA', 'DZSI', 'GECCL', 'HALO', 'IPKW', 'SBFGP', 'APPS', 'RAND', 'CDMOP', 'NVCN', 'SAGE', 'CRWS', 'JRSH', 'ROIC', 'YECO', 'CALM', 'PSMT', 'TELL', 'ANGI', 'CNOB', 'ESES', 'NMIH', 'TOWN', 'WHF', 'ABAC', 'CTIB', 'EIGR', 'EYES', 'PRPO', 'STNL', 'ADTN', 'CBAN', 'INTC', 'OPTT', 'SLM', 'ACET', 'GRBK', 'PIZ', 'SHSP', 'SIEB', 'SQQQ', 'SYKE', 'IBOC', 'INOD', 'CBSHP', 'JSM', 'PBIP', 'BHACR', 'FFBCW', 'GNST', 'GRBIC', 'HEES', 'MZOR', 'PDBC', 'ACHC', 'EBAYL', 'FSAC', 'MDRX', 'NRC', 'AMGN', 'COLM', 'CVTI', 'GRMN', 'HQCL', 'SUNW', 'UBX', 'ANGO', 'CETXW', 'DARE', 'LAKE', 'RCON', 'FGEN', 'FUNC', 'LFACW', 'NICK', 'SINO', 'NESRW', 'EMCI', 'RAIL', 'TUSK', 'NEWTZ', 'STPP', 'UCBI', 'DSKE', 'ARCI', 'IXUS', 'LSXMA', 'RELV', 'SVVC', 'ZBIO', 'SEED', 'SGMS', 'STLD', 'UBFO', 'INSY', 'KCAP', 'NATR', 'VUSE', 'CALI', 'CNFR', 'CONN', 'ENTA', 'VGLT', 'CVBF', 'MEDP', 'VERI', 'VIRT', 'CTHR', 'DTUL', 'FOLD', 'LFACU', 'PULM', 'AINV', 'INDY', 'PDFS', 'EBAY', 'GSKY', 'PDLB', 'HURN', 'ORMP', 'PMBC', 'NGHCN', 'PERY', 'CFO', 'DWCR', 'GRFS', 'PAVM', 'RSYS', 'SLNOW', 'UDBI', 'HQY', 'KBLMR', 'OHAI', 'ATLC', 'CHEKZ', 'INSG', 'RMTI', 'ENTG', 'FFBC', 'XEL', 'BWINB', 'CLDC', 'HSGX', 'LTXB', 'SBLKZ', 'AEHR', 'AMCN', 'AMRHW', 'FLIC', 'FV', 'LABL', 'OPTN', 'DRIOW', 'OPESW', 'HFGIC', 'LE', 'MATR', 'LOOP', 'WMGIZ', 'FDBC', 'KTWO', 'SCHL', 'CGO', 'CORV', 'ABEO', 'FORD', 'INO', 'INSE', 'CSA', 'RXIIW', 'CATB', 'EARS', 'BBOX', 'INDU', 'ISHG', 'EMCG', 'OMER', 'OPESU', 'RSLS', 'GNMK', 'TLGT', 'OPGNW', 'ARCC', 'AXON', 'LSXMK', 'RRGB', 'SCHN', 'CORT', 'LOVE', 'ABDC', 'IBKCO', 'ILMN', 'SHOO', 'AMRS', 'FPA', 'RMBL', 'TROW', 'AGYS', 'EPIX', 'GHDX', 'HFBL', 'PSCU', 'TDIV', 'RIOT', 'FULT', 'LEGR', 'MITK', 'NHLD', 'SVBI', 'CIZN', 'NEOG', 'TIBR', 'ANCX', 'AUDC', 'MCEP', 'FMAO', 'FOXA', 'SORL', 'SSRM', 'WMGI', 'DWCH', 'EBMT', 'EVER', 'SNLN', 'TBNK', 'OCC', 'ORG', 'RGCO', 'SENEA', 'SSC', 'ZEUS', 'CALA', 'CTAS', 'FBNK', 'UBNT', 'MLVF', 'FHB', 'GIGM', 'GTIM', 'KBAL', 'SINA', 'BKYI', 'SNHNI', 'VRIG', 'APLS', 'WWD', 'AVXL', 'SHIPW', 'TOUR', 'WSTG', 'CRZO', 'SYPR', 'VIVE', 'CMTL', 'OPBK', 'EQIX', 'STLR', 'BGCP', 'CID', 'RP', 'SHOS', 'CPLP', 'EDIT', 'FCA', 'CDXS', 'CSOD', 'LMFA', 'TCBIW', 'VRSN', 'CUR', 'RFAP', 'DALI', 'GOGL', 'JMBA', 'OMEX', 'PID', 'INOV', 'NDRA', 'WSBC', 'BSQR', 'CVGW', 'GPAQU', 'PLPC', 'TILE', 'BIB', 'FRAN', 'NSIT', 'RICK', 'CFA', 'FPXI', 'RRD', 'SANW', 'SPRT', 'CRESY', 'HUNT', 'PACB', 'PSTI', 'BRKS', 'CLRBZ', 'INSM', 'BRQS', 'OESX', 'PLLL', 'MBTF', 'PRIM', 'VERU', 'ATTU', 'GOODP', 'DFBHU', 'XPLR', 'KNSA', 'MSBI', 'QURE', 'RUSHA', 'EXFO', 'CCMP', 'GPAQW', 'SRCE', 'TCGP', 'ADBE', 'DMPI', 'RWLK', 'UTHR', 'AIRT', 'AMOT', 'ECYT', 'NCLH', 'PETS', 'TPIV', 'TRUP', 'BOFIL', 'EBTC', 'NLST', 'ONTX', 'IMDZ', 'LHCG', 'MAYS', 'WTFC', 'ACTG', 'EAGLU', 'RNDB', 'CATH', 'EMIF', 'IPGP', 'LMST', 'MCFT', 'COHR', 'DELT', 'DFBHW', 'FB', 'QQEW', 'RNMC', 'RVEN', 'SLS', 'EBIX', 'MNOV', 'PIH', 'TACO', 'BPY', 'GNMA', 'WSCI', 'LIVN', 'NGHCP', 'QADB', 'VIVO', 'AMMA', 'ANSS', 'CHNR', 'MGNX', 'AIRR', 'AMOV', 'CWAY', 'IPAR', 'KERX', 'PETQ', 'PPSI', 'RFEM', 'LCAHU', 'FBNC', 'EAGLW', 'FISI', 'SITO', 'ARGX', 'CHCO', 'EYEG', 'LKFN', 'TAIT', 'SRDX', 'UONEK', 'MRUS', 'RDHL', 'AAL', 'AIPT', 'CDOR', 'USAK', 'PAHC', 'YOGA', 'BKEP', 'SHEN', 'CODA', 'GBLIL', 'SGMA', 'CIL', 'DTEA', 'LCAHW', 'LMB', 'PROV', 'RLJE', 'PUB', 'GSIT', 'HA', 'UIHC', 'RDVY', 'EYPT', 'JAZZ', 'SNHY', 'SWKS', 'WIFI', 'NEOS', 'ASET', 'OLED', 'CASM', 'CNBKA', 'ESG', 'GLAD', 'GMLPP', 'FOSL', 'GAIA', 'SGMO', 'AYTU', 'BRPAW', 'CERN', 'MMDM', 'MMSI', 'NSYS', 'UMBF', 'WIRE', 'ALNA', 'CYTXW', 'KIRK', 'LJPC', 'MLNT', 'SWIR', 'TBBK', 'GCVRZ', 'MTBCP', 'MTGE', 'PTSI', 'ALDX', 'AMSWA', 'KFFB', 'SCVL', 'SFLY', 'TLC', 'TSRO', 'WDFC', 'RIBTW', 'ACRS', 'IJT', 'TRST', 'XBIO', 'QQQ', 'VONV', 'STRS', 'FLEX', 'FPAY', 'NCBS', 'NGHCZ', 'RELL', 'OTTR', 'QAT', 'AMBCW', 'PIXY', 'RYTM', 'AAON', 'ACNB', 'BCTF', 'BRPAU', 'AMAG', 'HWCC', 'CWBR', 'JASO', 'PSCE', 'AMZN', 'CHCI', 'AUTL', 'CPAH', 'FBMS', 'IFEU', 'PYZ', 'UEPS', 'CSTE', 'SVA', 'CASI', 'FTC', 'JOBS', 'LBIX', 'NAVG', 'PCAR', 'TYHT', 'ALXN', 'FMB', 'PNRG', 'RFEU', 'RGSE', 'KRMA', 'QTEC', 'SBCF', 'BIOL', 'MTRX', 'OXBR', 'UFCS', 'CTSH', 'DNLI', 'PLUG', 'BOMN', 'CZNC', 'FFIC', 'OSIS', 'PRCP', 'BRACR', 'GILD', 'HTBI', 'PRSS', 'CNACR', 'EMB', 'ESXB', 'FNX', 'LVHD', 'QRTEB', 'SUSC', 'AIHS', 'CCOI', 'DOTAR', 'FGM', 'FTA', 'HCKT', 'HSTM', 'NMRD', 'POOL', 'PEY', 'TAX', 'ABUS', 'VVPR', 'AVNW', 'EFAS', 'FNHC', 'INCY', 'SBBP', 'SSTI', 'DFVS', 'FTFT', 'HTGM', 'TMSR', 'WVVI', 'HCAP', 'NXST', 'CDEV', 'CSII', 'STAY', 'TAYD', 'TSRI', 'GPAQ', 'MELI', 'HTBK', 'JCTCF', 'PAVMW', 'SEDG', 'NFLX', 'DGII', 'HBAN', 'MAMS', 'BCACR', 'MTBC', 'SBLK', 'VRTX', 'GBLIZ', 'LEXEB', 'STNLU', 'TATT', 'GSM', 'NEBU', 'ALNY', 'PSCC', 'ROKU', 'ESTR', 'FYT', 'JSMD', 'VUZI', 'WINS', 'EXPD', 'NTCT', 'SNGX', 'GNUS', 'LAWS', 'TUR', 'WMIH', 'XENT', 'ANCB', 'BILI', 'CHUY', 'CVGI', 'MRLN', 'OMCL', 'RDI', 'ATNX', 'ESQ', 'NAVI', 'SCZ', 'XTLB', 'ALOT', 'BELFB', 'PMTS', 'SYNT', 'WHFBL', 'FJP', 'STNLW', 'EVGN', 'GDEN', 'HVBC', 'AMRK', 'CSGP', 'FLGT', 'OPES', 'QRHC', 'SSFN', 'UBIO', 'PSCM', 'TTS', 'ALDR', 'VMET', 'ANIK', 'AXDX', 'IMGN', 'EML', 'EWBC', 'FEMB', 'HTHT', 'IPCI', 'TREE', 'BLIN', 'CASA', 'GPRE', 'HOVNP', 'PYDS', 'WTBA', 'MTSC', 'CPSI', 'CIZ', 'FNKO', 'MCHI', 'CMSSR', 'FCAP', 'IOSP', 'MGTX', 'MLNX', 'MRAM', 'RMCF', 'CRNT', 'FAST', 'GPOR', 'HAYN', 'THRM', 'FLAG', 'FYX', 'GGAL', 'OPOF', 'RNEM', 'UBSH', 'BVNSC', 'ESCA', 'NEWA', 'URBN', 'EEFT', 'NXTD', 'HRZN', 'PFSW', 'WLTW', 'RRR', 'SANM', 'WEBK', 'BLCN', 'LWAY', 'SBBX', 'VTIQU', 'ARDX', 'LMRKO', 'GLBS', 'PSCI', 'SIGA', 'AVHI', 'GIFI', 'GLIBA', 'RBNC', 'RDUS', 'ALBO', 'CFFI', 'GFNCP', 'GOOD', 'OCSL', 'VRNT', 'AHPA', 'FTSM', 'HOLX', 'LPCN', 'STKL', 'UEIC', 'BLUE', 'CETV', 'HLG', 'CYCCP', 'STRA', 'MVIS', 'AGLE', 'CHSCM', 'OBNK', 'VKTX', 'BMRN', 'HBANO', 'VTIQW', 'FCAL', 'MBOT', 'PI', 'VBFC', 'XOMA', 'BOSC', 'JSML', 'MBFI', 'UCTT', 'IRDM', 'LITE', 'MTP', 'WLDN', 'HMNF', 'NVTR', 'ABP', 'ASV', 'GRPN', 'LIND', 'MNTX', 'BKSC', 'IROQ', 'NWBI', 'TWMC', 'ENTXW', 'ZNWAA', 'BPTH', 'CHSCO', 'GBDC', 'MTSI', 'SYNL', 'TTNP', 'AAXN', 'DNJR', 'TRNS', 'VRCA', 'XERS', 'TANNL', 'TST', 'FCAN', 'FOMX', 'LARK', 'ACGL', 'BSTC', 'LNDC', 'BCAC', 'DOX', 'MRCC', 'STXB', 'ZIV', 'GEMP', 'INFI', 'PLYA', 'WDAY', 'OPHT', 'RECN', 'CASY', 'DEPO', 'DLBL', 'IEA', 'AMNB', 'LLIT', 'PNQI', 'CYBE', 'ADP', 'OKTA', 'PXLW', 'MDIV', 'OBCI', 'ORRF', 'SEAC', 'VTC', 'LAMR', 'MBIO', 'CBIO', 'CHEF', 'MDGS', 'PEIX', 'ADES', 'GILT', 'PRSC', 'TRCB', 'ADRD', 'CELGZ', 'CETX', 'PKW', 'TGA', 'WDC', 'OSN', 'STBA', 'CNAT', 'GPRO', 'QINC', 'URGN', 'DGICA', 'FIVE', 'PKBK', 'SYNH', 'AAXJ', 'DLHC', 'VNET', 'ZN', 'CLUB', 'GTYH', 'IMMR', 'MDCA', 'VTIQ', 'AKTS', 'SLQD', 'XELB', 'CHKE', 'DXYN', 'MFSF', 'PHO', 'SIGI', 'MBII', 'ODFL', 'PGLC', 'WINA', 'CDZI', 'HDP', 'TFSL', 'AHPI', 'IPDN', 'JAKK', 'NODK', 'BVXV', 'CRAY', 'SCOR', 'ENSG', 'MOGO', 'USAU', 'KRNT', 'LONE', 'CLRO', 'FSFG', 'MYSZ', 'TORC', 'GSHTW', 'IMMP', 'MYNDW', 'REPH', 'LACQ', 'KMPH', 'DTRM', 'KVHI', 'PLUS', 'PBHC', 'SMCP', 'YNDX', 'AGNC', 'FTRI', 'HSDT', 'MRBK', 'PANL', 'TGLS', 'INFO', 'DISCK', 'IVFGC', 'OPB', 'RESN', 'CASS', 'CHFS', 'JVA', 'MOSY', 'PTEN', 'UBOH', 'CATYW', 'GOLD', 'GSHTU', 'DERM', 'LRCX', 'CMSS', 'HYRE', 'SHPG', 'SIGM', 'FTXR', 'LPLA', 'NH', 'TENX', 'BATRK', 'BHAC', 'EWZS', 'IAM', 'LGCY', 'TRCH', 'MLCO', 'VCSH', 'CENT', 'FSNN', 'MGPI', 'STRM', 'HNDL', 'INPX', 'ISTR', 'NEO', 'SMTX', 'SRPT', 'VRML', 'BHTG', 'IEI', 'FDUSL', 'ARTW', 'AXGN', 'BLBD', 'DINT', 'MDCO', 'MXIM', 'NANO', 'TANNZ', 'DRAD', 'NVAX', 'SWIN', 'CAMT', 'PFIE', 'PGC', 'TFIG', 'VIST', 'FTXL', 'TMUS', 'WING', 'ESBK', 'KOSS', 'BLNK', 'CSBR', 'XSPA', 'DBVT', 'GOV', 'MPWR', 'NTLA', 'NTRSP', 'PESI', 'PVAL', 'SNNA', 'PCTY', 'SGLB', 'LANC', 'LBRDK', 'SCAC', 'MCRB', 'RIBT', 'TNDM', 'ISRG', 'KPTI', 'VSEC', 'Z', 'EMXC', 'RCMT', 'IKNX', 'SOHOO', 'ALLT', 'BZUN', 'CLLS', 'NEXT', 'ULBI', 'WKHS', 'BLDP', 'CSIQ', 'FNTE', 'FTXN', 'STAA', 'UBCP', 'ZBRA', 'COWN', 'GDS', 'IDXG', 'PMPT', 'RILYH', 'SGH', 'SRTSW', 'NYMTO', 'SGRY', 'TEAM', 'CDLX', 'CEZ', 'FIXX', 'FORTY', 'CENX', 'DISCA', 'XNET', 'MU', 'CLRG', 'PTC', 'QTNT', 'COMT', 'GOOGL', 'HNNA', 'ROAD', 'SNSR', 'AY', 'PY', 'TRPX', 'CAMP', 'FIZZ', 'QLC', 'SASR', 'SRNE', 'ARNA', 'BLDR', 'FTXH', 'MNDO', 'ONB', 'CNMD', 'DWPP', 'OSBCP', 'EMKR', 'FCBP', 'NBTB', 'SNES', 'ATXI', 'INVA', 'UHAL', 'QCLN', 'LBAI', 'PTLA', 'SRAX', 'SSKN', 'VTWV', 'OTEL', 'CPSS', 'DNKN', 'EVOP', 'JD', 'LBTYB', 'TRNC', 'CROX', 'ESGG', 'MHLD', 'PODD', 'CSSEP', 'HBK', 'SOHOK', 'TSLA', 'BCOV', 'KALV', 'TNXP', 'LGCYO', 'MILN', 'RILYL', 'SURF', 'TTPH', 'CHRW', 'VIA', 'EUFN']

class CustomFaker(BaseProvider):
    def gender(self):
        genders = ['M', 'F']
        return random.choice(genders)

    def phonetype(self):
        phoneTypes = ["home", "office", "personal", "mobile", "cell"]
        return random.choice(phoneTypes)

    def random_string(self, str_len=6):
        return ''.join([random.choice(string.ascii_letters) for _ in range(str_len)])

    def datetime_now(self):
        return str(datetime.datetime.now())

    def symbol(self):
        return random.choice(symbols)

def __genPerson(fake):
    personId = random.randint(1, maxNum)
    person = {}
    person["personid"] = personId
    person["title"] = fake.suffix()
    person["firstname"] = fake.first_name()
    person["lastname"] = fake.last_name()
    person["job"] = fake.job()
    person["email"] = fake.free_email()
    randCols = __genRandomCols(fake, "person", numCols = 9)
    person = {**person, **randCols}
    return person

def __genRandomCols(fake, prefix, numCols=9):
    formats = ['word', 
        'domain_name', 
        'color_name', 
        'currency_code'
    ]
    randCols = {}
    for idx in range(1, numCols+1):
        col = "{}_{}".format(prefix, idx)
        format = formats[(idx-1)%len(formats)]
        randCols[col] = getattr(fake, format)()
    return randCols

def __genTransactions(fake):
    transacList = []
    for idx in range(random.randint(5, 15)):
        transac = {}
        transac['transactionid'] = random.randint(1, maxNum)
        transac['companyid'] = fake.symbol()
        transac['countrycode'] = fake.country_code()
        transac['quantity'] = random.randint(1, 10000)
        transac['unitprice'] = random.uniform(10, 1000)
        transac['usdvalue'] = random.uniform(10, 500)
        transac['sellbuy'] = random.choice(["buy", "sell"])
        randCols = __genRandomCols(fake, "transaction", numCols = 10)
        transac = {**transac, **randCols}
        transacList.append(transac)
    return transacList

def __getLastNPairsDates(n=30):
    today = date.today()
    datePairs = []
    prev = None
    for i in range(n, -1, -1):
        nxt = today - timedelta(i)
        if prev:
            datePairs.append((str(prev), str(nxt)))
            prev = None
        else:
            prev = nxt
    if prev:
        datePairs.append((str(prev), str(prev)))
    return datePairs

def genData(filepath, instream, imd=False):
    inObj = json.loads(instream.read())
    if inObj["numRows"] == 0:
        return
    start = inObj["startRow"] + 1
    end = start + inObj["numRows"]

    fake = Faker()
    fake.add_provider(CustomFaker)
    
    while start < end:
    	modDate = fake.datetime_now()
    	person = __genPerson(fake)
    	for transac in __genTransactions(fake):
            res = {**transac, **person}
            res['opcode'] = 2 if imd else 1
            res['modifieddate'] = modDate
            yield res
            start += 1
