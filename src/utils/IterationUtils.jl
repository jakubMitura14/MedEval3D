"""
Holds collection of functions - mainly macros that when invoked from inside of the kernel will lead to iteration
Generally by convention we will use UInt32 as this is a format of threadid.x and other basic CUDA variables
arr - 3 dimensional data we analyze
maxX maxY maxZ- we will need also to supply data for variables called maxX maxY maxZ (if we have 3 dimensional loop) - those will create boundary checks  - for 2 dimensional case we obviously need only max X and max Y
minX, minY and minZ - this are assumed to be 1 if not we can supply them in the macro
loopX, loopY,loopZ - how many iterations should be completed while iterating over given dimension

we need also to supply functions of iterating the 3 dimensional data but with chosen dimension fixed - 
  so for example if we want to analyze top padding from shared memory we will set the dimension 3 at 1
"""
module IterationUtils
using CUDA,Logging
export @iter3d, @iter3dAdditionalxyzActsAndZcheck, @iter3dAdditionalxyzActs, @iter3dAdditionalzActs

"""
arrDims- dimensions of main arrya
loopIterNameX ,loopIterNameY, loopIterNameZ  - variable name that will be used in a left hand side of loop
xname,yname,zname - symbols representing the x,y and z that are calculated for currnt position
xDimName,yDimName,zDimName - symbols representing the left hand sides of the loop
loopDims- information how many times we need to loop over given dimension
zOffset,zAdd - calculate offset and thread/block dependent add 
Offset,xOffset,xAdd, yAdd - offsets for x and y  and what to add to them
xCheck,yCheck,zCheck - checks performed just after for - and determining wheather to continue
additionalActionAfterZ,additionalActionAfterY,additionalActionAfterX  - gives possibility of invoking more actions  
    - invoked after the checks (checks are avoided to prevent warp stall if warp sync will be invoked)
is3d - if true we use 3 dimensional loop if not we iterate only over x and y 
isFullBoundaryCheckX, isFullBoundaryCheckY, isFullBoundaryCheckZ - indicates wheather we want to check boundaries on all iterations if false it will be done only on last iteration if not stated explicitely to avoid all boundary checks
nobundaryCheckX, nobundaryCheckY, nobundaryCheckZ - true if we want to avoid completely boundary checks

ex - main expression around which we build loop  
"""
macro iter3d(arrDims,loopXdim,loopYdim,loopZdim   ,ex   )
  mainExp = generalizedItermultiDim(; arrDims=arrDims,loopXdim ,loopYdim,loopZdim, ex = ex)  
  return esc(:( $mainExp))
  end#iter3d

"""
modification of iter3d loop  where wa allow additional action after z check
"""
macro iter3dAdditionalxyzActsAndZcheck(arrDims,loopXdim,loopYdim,loopZdim,zCheck
  ,ex,additionalActionAfterX,additionalActionAfterY,additionalActionAfterZ)
  mainExp = generalizedItermultiDim(; arrDims=arrDims,loopXdim=loopXdim ,loopYdim=loopYdim,loopZdim=loopZdim,zCheck=zCheck, ex=ex
  ,additionalActionAfterX=additionalActionAfterX ,additionalActionAfterY=additionalActionAfterY
  ,additionalActionAfterZ=additionalActionAfterZ )  

  return esc(:( $mainExp))
end#iter3dAdditionalxyzActs


"""
modification of iter3d loop  where wa allow additional actions to be performed after each loop check
"""
macro iter3dAdditionalzActs(arrDims, loopXdim,loopYdim,loopZdim,ex,additionalActionAfterZ)

  mainExp = generalizedItermultiDim(; arrDims=arrDims,loopXdim=loopXdim ,loopYdim=loopYdim,loopZdim=loopZdim
  ,additionalActionAfterZ=additionalActionAfterZ, ex = ex )  

  return esc(:( $mainExp))
end#iter3dAdditionalxyzActs

"""
generalized version of iter3d we will specilize it in the macro on the basis of multiple dispatch
  arrDims- dimensions of main arrya
  loopIterNameX ,loopIterNameY, loopIterNameZ  - variable name that will be used in a left hand side of loop
  xname,yname,zname - symbols representing the x,y and z that are calculated for currnt position
  xDimName,yDimName,zDimName - symbols representing the left hand sides of the loop
  loopXdim, loopYdim,loopZdim - information how many times we need to loop over given dimension
  zOffset,zAdd - calculate offset and thread/block dependent add 
  Offset,xOffset,xAdd, yAdd - offsets for x and y  and what to add to them
  xCheck,yCheck,zCheck - checks performed just after for - and determining wheather to continue
  additionalActionAfterZ,additionalActionAfterY,additionalActionAfterX  - gives possibility of invoking more actions  
      - invoked after the checks (checks are avoided to prevent warp stall if warp sync will be invoked)
  is3d - if true we use 3 dimensional loop if not we iterate only over x and y 
  isFullBoundaryCheckX, isFullBoundaryCheckY, isFullBoundaryCheckZ - indicates wheather we want to check boundaries on all iterations if false it will be done only on last iteration if not stated explicitely to avoid all boundary checks
  nobundaryCheckX, nobundaryCheckY, nobundaryCheckZ - true if we want to avoid completely boundary checks
  
  ex - main expression around which we build loop    
"""
function generalizedItermultiDim(; #we keep all as keyword arguments
  arrDims = (UInt32(1),UInt32(1),UInt32(1) )
   ,xname = :x
   ,yname = :y
   ,zname = :z
   ,loopIterNameX = :xdim
   ,loopIterNameY = :ydim
   ,loopIterNameZ = :zdim    
   ,loopXdim = 1
   ,loopYdim= 1
   ,loopZdim= 1
  ,zOffset= :(zdim*gridDim().x)
   ,zAdd =:(blockIdxX())
  ,yOffset = :(ydim* blockDimY())
  ,yAdd= :(threadIdxY())
  ,xOffset= :(xdim * blockDimX())
   ,xAdd= :(threadIdxX())
  ,xCheck = :(x <= $arrDims[1])
  ,yCheck = :(y <= $arrDims[2])
  ,zCheck = :(z <= $arrDims[3])    
  ,additionalActionAfterZ= :()
   ,additionalActionAfterY= :()
   ,additionalActionAfterX = :()
   , is3d = true
   ,ex 
   ,isFullBoundaryCheckX =false
   , isFullBoundaryCheckY=false
   , isFullBoundaryCheckZ=false
   ,nobundaryCheckX=false
   , nobundaryCheckY=false
   , nobundaryCheckZ =false)
#we will define expressions from deepest to most superficial

# ,zOffset= :($loopIterNameZ*gridDim().x)
# ,zAdd =:(blockIdxX())
# ,yOffset = :($loopIterNameY* blockDimY())
# ,yAdd= :(threadIdxY())
# ,xOffset= :($loopIterNameX * blockDimX())

  # xState = :(x= $xOffset +$xAdd)
  # yState = :(y= $yOffset +$yAdd)
  # zState = :(z= $zOffset +$zAdd)
  # xState = :($xname= $xOffset +$xAdd)
  # yState = :($yname= $yOffset +$yAdd)
  # zState = :($zname= $zOffset +$zAdd)
  

  exp1= :()
  if(isFullBoundaryCheckX)
    exp1 = quote
      @unroll for $loopIterNameX in 0:$loopXdim
          $xname= $xOffset +$xAdd
          if( $xCheck)
            $ex
          end#if x
        $additionalActionAfterX  
        end#for x dim
      end#quote
  elseif(nobundaryCheckX)
    exp1 = quote
      @unroll for $loopIterNameX in 0:$loopXdim
          $xname= $xOffset +$xAdd
            $ex
        $additionalActionAfterX  
        end#for x dim
      end#quote


  else
    exp1 = quote
      @unroll for $loopIterNameX in 0:$loopXdim-1
          $xname= $xOffset +$xAdd
          $ex
          $additionalActionAfterX 
      end#for x dim
      
      $loopIterNameX=$loopXdim
      $xname= $xOffset +$xAdd
        if( $xCheck)
          $ex
        end#if x     
      $additionalActionAfterX  
      end#quote
  end  



  exp2= :()
if(isFullBoundaryCheckY)
    exp2= quote
      @unroll for $loopIterNameY in  0:$loopYdim
        $yname = $yOffset +$yAdd
          if($yCheck)
            $exp1
          end#if y
          $additionalActionAfterY
          end#for  yLoops 
        end#quote
elseif(nobundaryCheckY)
  exp2= quote
    @unroll for $loopIterNameY in  0:$loopYdim
      $yname = $yOffset +$yAdd
          $exp1
        $additionalActionAfterY
        end#for  yLoops 
      end#quote
else
  exp2= quote
    @unroll for $loopIterNameY in  0:$loopYdim-1
      $yname = $yOffset +$yAdd
        $exp1
        $additionalActionAfterY
    end#for  yLoops 
        $loopIterNameY=$loopYdim
        $yname = $yOffset +$yAdd
        if($yCheck)
          $exp1
        end#if y
        $additionalActionAfterY
      end#quote
end

############################### z 
if(isFullBoundaryCheckZ)
        exp3= quote
          @unroll for $loopIterNameZ in 0:$loopZdim
            $zname = $zOffset + $zAdd#multiply by blocks to avoid situation that a single block of threads would have no work to do
            if($zCheck)          
              $exp2
            end#if z 
            $additionalActionAfterZ  
        end#for z dim
        end 

elseif(nobundaryCheckZ)
        exp3= quote
          @unroll for $loopIterNameZ in 0:$loopZdim
            $zname = $zOffset + $zAdd#multiply by blocks to avoid situation that a single block of threads would have no work to do
              $exp2
            $additionalActionAfterZ  
        end#for z dim
        end 
 else
        exp3= quote
          @unroll for $loopIterNameZ in 0:$loopZdim-1
            $zname = $zOffset + $zAdd#multiply by blocks to avoid situation that a single block of threads would have no work to do
            $exp2
            $additionalActionAfterZ  
        end#for z dim
        $loopIterNameZ=$loopZdim
        $zname = $zOffset + $zAdd
        if($zCheck)          
          $exp2
        end#if z 

        end 
end

if(is3d)
  return exp3
end  
#if 2d 
return exp2

end#generalizedIter3d

"""
give loop where we  test only last iteration for boundary conditions

  loopIterName - variable name that will be used in a left hand side of loop
  loopDim - as many times we will loop starting from 0 
  offset, addToOffset - variables that are used for calculating varName
  additionalActionAfter -  the function evaluated outside of the check
  checkFun - evaluated to check weather we should evaluate ex
  noCheck - we will not evaluate check expression before evaluating ex
  allCheck - we will always evaluate check expression before evaluating ex
  ex - main expression evaluated in the loop

"""
function getSubLoopPartialCheck(loopIterName,loopDim,defineVariable, additionalActionAfter ,checkFun,noCheck,allCheck,ex )



  oneCheckEx = quote

    CUDA.@cuprint("     aaaaaaaaaaa  \n")
    CUDA.@cuprint("     aaaaaaaaaaa  \n")
    CUDA.@cuprint("     aaaaaaaaaaa  \n")
    CUDA.@cuprint("     aaaaaaaaaaa  \n")

    @unroll for $loopIterName::UInt32 in  0:($loopDim-1)  # we subtract one as we are intrsted only for those iterations that will not need to be bound checked
      x=1;y=1;z=1
      $defineVariable     
        $ex
        $additionalActionAfter
    end#for   
    if($checkFun)
          $ex
    end#if 
    $additionalActionAfter
  end


  allCheckEx = quote

    CUDA.@cuprint("     bbbbbbbbbb  \n")
    CUDA.@cuprint("     bbbbbbbbbb  \n")
    CUDA.@cuprint("     bbbbbbbbbb  \n")
    CUDA.@cuprint("     bbbbbbbbbb  \n")


    @unroll for $loopIterName::UInt32 in  0:($loopDim-1)  # we subtract one as we are intrsted only for those iterations that will not need to be bound checked
     $defineVariable
    if($checkFun)
          $ex
    end#if 
    $additionalActionAfter
    end#for 
  end


  noCheckEx = quote

    CUDA.@cuprint("     ccc  \n")
    CUDA.@cuprint("     ccc  \n")
    CUDA.@cuprint("     ccc  \n")
    CUDA.@cuprint("     ccc  \n")


    @unroll for $loopIterName::UInt32 in  0:($loopDim-1)  # we subtract one as we are intrsted only for those iterations that will not need to be bound checked
     $defineVariable
        $ex
        $additionalActionAfter
    end#for 
   
  end
  #will return diffrent expressions depending on given booleans
  if(noCheck)
    return noCheckEx
  elseif(allCheck)    
    return allCheckEx
  else
    return oneCheckEx
  end  

end



"""
iteration through 3 dimensional data but  with one dimension fixed - ie we will analyze plane or part of the plane where value of given dimension is as we supply it 
this can be used to analyze for example padding in the stencil - of course it may lead to non coalesced memory access 
chosenDim (1,2 or 3) - the dimension of choice through which we are NOT iterating
dimValue - value of this dimension that we will keep fixed
        DimA, DimB - those dimensions will be chosen to iterate over (macro will analyze those on its own - no need to supply them explicitely)
              - in case chosenDim = 1  DimA, DimB will be 2,3 
              - in case chosenDim = 2  DimA, DimB will be 1,3 
              - in case chosenDim = 3  DimA, DimB will be 1,2
maxDimA, maxDimB - maximum values available in source array
loopDimA, loopDimB - how many times we should iterate in those dimensions

"""
macro iterDimFixed(chosenDim, dimValue,maxDimA, maxDimB,loopDimA, loopDimB  )

end#iterDimFixed


end#module


# function generalizedIter3d( arrDims, loopXdim, loopYdim,loopZdim,zOffset,zAdd ,ex  )
#   quote
#     @unroll for zdim::UInt32 in 0:$loopZdim
#       z::UInt32 = (zdim*gridDim().x) + blockIdxX()#multiply by blocks to avoid situation that a single block of threads would have no work to do
#       if( (z<= $arrDims[3]) )    
#           @unroll for ydim::UInt32 in  0:$loopYdim
#               y::UInt32 = ((ydim* blockDimY()) +threadIdxY())
#                 if( (y<=$arrDims[2])  )
#                   @unroll for xdim::UInt32 in 0:$loopXdim
#                       x::UInt32=(xdim* blockDimX()) +threadIdxX()
#                       if((x <=$arrDims[1]))
#                         $ex
#                       end#if x
#                  end#for x dim 
#             end#if y
#           end#for  yLoops 
#       end#if z   
#   end#for z dim
#   end 



# function generalizedIter3dFullChecks( arrDims, loopXdim, loopYdim,loopZdim,zOffset,zAdd,yOffset,xOffset,ex  )
#   quote
#     @unroll for zdim::UInt32 in 0:$loopZdim
#       z::UInt32 = $zOffset + $zAdd#multiply by blocks to avoid situation that a single block of threads would have no work to do
#       if( (z<= $arrDims[3]) )    
#           @unroll for ydim::UInt32 in  0:$loopYdim
#               y::UInt32 = $yOffset +threadIdxY()
#                 if( (y<=$arrDims[2])  )
#                   @unroll for xdim::UInt32 in 0:$loopXdim
#                       x::UInt32= $xOffset +threadIdxX()
#                       if((x <=$arrDims[1]))
#                         $ex
#                       end#if x
#                  end#for x dim 
#             end#if y
#           end#for  yLoops 
#       end#if z   
#   end#for z dim
#   end 
# end#generalizedIter3d



# quote
#   @unroll for xdim::UInt32 in 0:($loopXdim-1) # we subtract one as we are intrsted only for those iterations that will not need to be bound checked
#     $xname::UInt32= $xOffset +threadIdxX()
#      $ex
#       $additionalActionAfterX  
#     end#for x dim
#     if( $xCheck)
#         $ex
#     end#if x
#      $additionalActionAfterX  
   
#     end#quote
 
  
# exp2= quote
#     @unroll for ydim::UInt32 in  0:($loopYdim-1)  # we subtract one as we are intrsted only for those iterations that will not need to be bound checked
#      $yname::UInt32 = $yOffset +threadIdxY()
    
#         $exp1
#         $additionalActionAfterY
#     end#for  yLoops 

#     if($yCheck)
#           $exp1
#     end#if y
#     $additionalActionAfterY
#   end

# exp3= quote
# @unroll for zdim::UInt32 in 0:$loopZdim # we subtract one as we are intrsted only for those iterations that will not need to be bound checked
#   $zname::UInt32 = $zOffset + $zAdd#multiply by blocks to avoid situation that a single block of threads would have no work to do
#     $exp2
#     $additionalActionAfterZ 
#  end#for z dim
# if($zCheck)    
#     $exp2
#   end#if z 
#   $additionalActionAfterZ  
















# function generalizedItermultiDim(; #we keep all as keyword arguments
#   arrDims = (UInt32(1),UInt32(1),UInt32(1) )
#    ,xname = :x
#    ,yname = :y
#    ,zname = :z
#    ,loopIterNameX = :xDim
#    ,loopIterNameY = :yDim
#    ,loopIterNameZ = :zDim    
#    ,loopXdim = 1
#    ,loopYdim= 1
#    ,loopZdim= 1
#   ,zOffset= :(($loopIterNameZ*gridDim().x))
#    ,zAdd =:(blockIdxX())
#   ,yOffset = :($loopIterNameY* blockDimY())
#   ,yAdd= :(threadIdxY())
#   ,xOffset= :($loopIterNameX * blockDimX())
#    ,xAdd= :(threadIdxX())
#   ,xCheck = :((x <= $arrDims[1]))
#   ,yCheck = :((y <= $arrDims[2]))
#   ,zCheck = :((z <= $arrDims[3]))    
#   ,additionalActionAfterZ= :()
#    ,additionalActionAfterY= :()
#    ,additionalActionAfterX = :()
#    , is3d = true
#    ,ex 
#    ,isFullBoundaryCheckX =false
#    , isFullBoundaryCheckY=false
#    , isFullBoundaryCheckZ=false
#    ,nobundaryCheckX=false
#    , nobundaryCheckY=false
#    , nobundaryCheckZ =false)
# #we will define expressions from deepest to most superficial

#   # xState = :(x= $xOffset +$xAdd)
#   # yState = :(y= $yOffset +$yAdd)
#   # zState = :(z= $zOffset +$zAdd)
#   # xState = :($xname= $xOffset +$xAdd)
#   # yState = :($yname= $yOffset +$yAdd)
#   # zState = :($zname= $zOffset +$zAdd)
#   xState = :($xname)
#   yState = :($yname)
#   zState = :($zname)

#   xCheck = :(true)
#   yCheck = :(true)
#   zCheck = :(true)    

#   exp1 = getSubLoopPartialCheck(loopIterNameX,loopXdim,xState, additionalActionAfterX ,xCheck ,isFullBoundaryCheckX, nobundaryCheckX,ex)
#   exp2 = getSubLoopPartialCheck(loopIterNameY,loopYdim,yState, additionalActionAfterY ,yCheck ,isFullBoundaryCheckY, nobundaryCheckY,exp1)
#   exp3 = getSubLoopPartialCheck(loopIterNameZ,loopZdim,zState, additionalActionAfterZ ,zCheck ,isFullBoundaryCheckZ, nobundaryCheckZ,exp2)

#   #if it is 3d we will return x,y,z iterations if not only x and y 
#   # if(is3d)
#   #   return exp3
#   # else
#   #   return exp2
#   # end

#   oneCheckEx = quote

#     CUDA.@cuprint("     aaaaaaaaaaa  \n")
#     CUDA.@cuprint("     aaaaaaaaaaa  \n")
#     CUDA.@cuprint("     aaaaaaaaaaa  \n")
#     CUDA.@cuprint("     aaaaaaaaaaa  \n")

#     @unroll for $loopIterNameX::UInt32 in  0:($loopXdim-1)  # we subtract one as we are intrsted only for those iterations that will not need to be bound checked
#       $xname= $xOffset +$xAdd  
#         $ex
#         $additionalActionAfterX
#     end#for   
#     if($xCheck)
#           $ex
#     end#if 
#     $additionalActionAfterX
#   end
# return oneCheckEx


# end#generalizedIter3d