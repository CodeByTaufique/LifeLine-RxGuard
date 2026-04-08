#!/bin/bash

# DataBase files to access them with short names
DB="./lifeLineData"
MEDS="$DB/medsInventory.txt"
BLOOD="$DB/bloodInventory.txt"
USER="$DB/systemUsers.txt"
LOG="$DB/auditTrail.txt"
BILL="$DB/patientBills.txt"
DONOR="$DB/donorDetails.txt"
BACKUP="$DB/backUps"
EMERGENCY="$DB/.activeEmergerncy"

# Mark active User as we have Pharpacist & Staff
activeUser=""
activeRole=""

# This will keep track of all things happens in the system
writeLog() {
    	local category="$1"
    	local message="$2"
    	echo "$(date '+%Y-%m-%d %H:%M:%S') | [$category] | User: $activeUser | $message" >> "$LOG"
}

# Setting DataBase so that if not exixt it creates one or load the previous one
dataBase() {
        if [[ ! -d "$DB" ]]; then
                mkdir -p "$DB"
        fi
        mkdir -p "$BACKUP"

        for file in "$MEDS" "$BLOOD" "$USER" "$LOG" "$BILL" "$DONOR"; do
                if [[ ! -f "$file" ]]; then
                        touch "$file"
                fi
        done
}

# This hepls wwhen billing is called
signature() {
        sigText=""
        issued=$(grep -i "Issued .* to Patient: $patient$" "$LOG")

        while read -r line; do
                qty=$(echo "$line" | sed -n 's/.*Issued \([0-9]\+\) units.*/\1/p')
                med=$(echo "$line" | sed -n 's/.*units of \(.*\) to Patient.*/\1/p')

                sigText="$sigText
		Patient:$patient | Med:$med | Qty:$qty | IssuedBy:$activeUser"
        done <<< "$issued"
}

# Check the expiry status for the meds
expiryStatus() {
        local targetDate="$1"
        local currentTime=$(date +%s)
        local expiryDate=$(date -d "$targetDate" +%s)

        if [[ -z "$expiryDate" ]]; then
                echo "UNKNOWN"
                return
        fi

        local secDiff=$(( expiryDate - currentTime ))
        local dayDiff=$(( secDiff / 86400 ))

        if [[ "$dayDiff" -lt 0 ]]; then
                echo "EXPIRED"
        elif [[ "$dayDiff" -le 7 ]]; then
                echo "CRITICAL"
        else
                echo "SAFE"
        fi
}

# Check and alert the low stock of any meds
lowStock() {
        local alertMsg=""
        while IFS='|' read -r name category qty price exp rest; do
                if [[ -n "$qty" ]] && [[ "$qty" -lt 5 ]]; then
                        alertMsg="${alertMsg}Item: $name (Remaining : $qty)\n"
                fi
        done < "$MEDS"
        if [[ -n "$alertMsg" ]]; then
                zenity --warning --title="Low Stock Alert!" \
                        --text="The following items are Low : \n\n$alertMsg"
        fi
}

#Add meds to the inventory
addMeds() {
        input=$(zenity --forms --title="Inventory Entry" --text="Register Medicine Stock" \
                --add-entry="Medicine Name" \
                --add-entry="Category (e.g. Antibiotic / Painkiller / Syrup)" \
                --add-entry="Quantity (Units)" \
                --add-entry="Price (Per Unit)" \
                --add-calendar="Expiry Date" \
                --add-list="Requires Permission?" --list-values="No|Yes")

        if [[ -z "$input" ]]; then
			return
		fi

        input=$(echo "$input" | tr -d '\r\n')
        medsName=$(echo "$input" | cut -d '|' -f1)
        medsCat=$(echo "$input" | cut -d '|' -f2)
        medsQty=$(echo "$input" | cut -d '|' -f3)
        medsPrice=$(echo "$input" | cut -d '|' -f4)
        medsExp=$(echo "$input" | cut -d '|' -f5)
        medsRest=$(echo "$input" | cut -d '|' -f6)

        if [[ -z "$medsQty" || ! "$medsQty" =~ ^[0-9]+$ ]]; then
                zenity --error --text="Invalid Quantity!"
                return
        fi

        if grep -qi "^$medsName|" "$MEDS"; then
                oldLine=$(grep -i "^$medsName|" "$MEDS")

                oldCat=$(echo "$oldLine" | cut -d '|' -f2)
                oldQty=$(echo "$oldLine" | cut -d '|' -f3)
                oldPrice=$(echo "$oldLine" | cut -d '|' -f4)
                oldRest=$(echo "$oldLine" | cut -d '|' -f6)

                newQty=$((oldQty + medsQty))

                grep -vi "^$medsName|" "$MEDS" > "$MEDS.tmp"
                echo "$medsName|$oldCat|$newQty|$oldPrice|$medsExp|$oldRest" >> "$MEDS.tmp"
                mv "$MEDS.tmp" "$MEDS"

                writeLog "PHARMACY" "Inventory Updated : $medsName ($oldCat), Added Qty: $medsQty, Total: $newQty"
                zenity --info --text="$medsName already exists.\n\nQuantity updated to $newQty\nExpiry replaced."

        else
                echo "$medsName|$medsCat|$medsQty|$medsPrice|$medsExp|$medsRest" >> "$MEDS"
                writeLog "PHARMACY" "Inventory Addition : $medsName ($medsCat), Qty: $medsQty"
                zenity --info --text="Successfully Registered $medsName in the Pharmacy!"
        fi
}

# Add new Blood Donors
manageDonors() {
    	donorInput=$(zenity --forms --title="Donor Management" --text="Add Donor Details" \
         	   --add-entry="Full Name" \
          	  --add-list="Blood Type" --list-values="A+|A-|B+|B-|O+|O-|AB+|AB-" \
          	  --add-entry="Phone Number" \
           	 --add-calendar="Registration Date")

		if [[ -z "$donorInput" ]]; then
   			 zenity --error --text="All fields are required!"
    		 return
		fi

		 name=$(echo "$donorInput" | cut -d '|' -f1)
         bloodType=$(echo "$donorInput" | cut -d '|' -f2)
         phone=$(echo "$donorInput" | cut -d '|' -f3)
         regDate=$(echo "$donorInput" | cut -d '|' -f4)

         if [[ -z "$name" || -z "$bloodType" || -z "$phone" || -z "$regDate" ]]; then
                 zenity --error --text="All fields are required!"
                 return
         fi
 
    	if [[ -n "$donorInput" ]]; then
        	echo "$donorInput" >> "$DONOR"
        	bloodType=$(echo "$donorInput" | cut -d '|' -f2)
        	found=0
      		tempFile="blood_temp.txt" > "$tempFile"

        	if [[ -f "$BLOOD" ]]; then
            	while IFS='|' read -r type count || [ -n "$type" ]; do
                	if [[ "$type" = "$bloodType" ]]; then
                    	count=$((count + 1))
                    	found=1
                	fi
                echo "$type|$count" >> "$tempFile"
            	done < "$BLOOD"
        	fi

        	if [[ $found -eq 0 ]]; then
            	echo "$bloodType|1" >> "$tempFile"
        	fi
			
        	mv "$tempFile" "$BLOOD"
        	writeLog "DONOR" "Registered Donor : $(echo "$donorInput" | cut -d '|' -f1)"
        	zenity --info --text="Donor Details Saved Successfully!"
    	fi
}

# Generates the bills for the patient
generateBill() {
        choice=$(zenity --list --title="Billing Options" \
                --column="Action" \
                "Manual Invoice" \
                "Generate from Issued Medicines")

        if [[ -z "$choice" ]]; then
		 	return
		fi

        if [[ "$choice" = "Manual Invoice" ]]; then

                billInput=$(zenity --forms --title="Financial Billing" --text="Invoice" \
						--width=550 --height=550 \
                        --add-entry="Patient Name" \
                        --add-list="Type" --list-values="Service|Medicine" \
                        --add-entry="Amount")
				if [[ -z "$billInput" ]]; then
    					zenity --error --text="All fields are required!"
    					return
				fi

				name=$(echo "$billInput" | cut -d '|' -f1)
                type=$(echo "$billInput" | cut -d '|' -f2)
                amount=$(echo "$billInput" | cut -d '|' -f3)

                if [[ -z "$name" || -z "$type" || -z "$amount" ]]; then
                        zenity --error --text="All fields are required!"
                        return
                fi
						
                if [[ -n "$billInput" ]]; then
                        echo "$(date +%F)|$billInput" >> "$BILL"
                        writeLog "BILLING" "Invoiced : $(echo "$billInput" | cut -d '|' -f1)"
                        zenity --info --text="Invoice Generated and Archived!"
                fi
        else
                patient=$(zenity --entry --title="Search Patient" \
                        --text="Enter Patient Name for Billing")

                if [[ -z "$patient" ]]; then
			 		return
				fi

                issued=$(grep -i "Issued .* to Patient: $patient$" "$LOG")

                if [[ -z "$issued" ]]; then
                        zenity --error --text="No issued medicines found for $patient"
                        return
                fi

                total=0
                details=""
                while read -r line; do
                        qty=$(echo "$line" | sed -n 's/.*Issued \([0-9]\+\) units.*/\1/p')
                        med=$(echo "$line" | sed -n 's/.*units of \([^ (]*\).*/\1/p')
                        price=$(grep "^$med|" "$MEDS" | cut -d '|' -f4)

                        if [[ -z "$price" ]]; then
							continue
						fi

                        cost=$((qty * price))
                        total=$((total + cost))
                        details="$details\n$med x$qty = $cost"

                done <<< "$issued"
		signature

		zenity --info \
        	--title="Auto Generated Bill" \
        	--width=700 \
        	--height=600 \
        	--no-wrap \
        	--text="Patient: $patient
Issued Medicines:
$details
Signature:
$sigText
Total Amount: $total"

echo "$(date +%F)|$patient|Medicine|$total" >> "$BILL"
                writeLog "BILLING" "Auto bill generated for Patient: $patient | Amount: $total"
        fi
}

# This just check that all required files of this system is present
healthCheck() {
    healthReport="🩺 LifeLine System Health Check\n\n"
    for file in "$MEDS" "$BLOOD" "$USER" "$LOG"; do
        if [[ -f "$file" ]]; then
            healthReport+=$(printf "✅ %-20s : Online\n" "$file")
        else
            healthReport+=$(printf "❌ %-20s : Missing\n" "$file")
        fi
    done

    zenity --info \
        --title="🩺 LifeLine - System Status" \
        --width=600 \
        --height=500 \
        --text="$healthReport" \
        --ok-label="Close" \
        --timeout=0
}

# This is for viewing the meds in inventory
viewInventory() {
        (
                while IFS='|' read -r name category qty price exp rest || [ -n "$name" ]; do
                        risk=$(expiryStatus "$exp" | tr -d '\n')
                        if [[ -z "$risk" ]]; then
                                risk="$exp"
                        fi

                        echo "$name"
                        echo "$category"
                        echo "$qty"
                        echo "$price"
                        echo "$risk"
                        echo "$rest"
                done < "$MEDS"
        ) | zenity --list \
                --title="💊 LifeLine Pharmacy Inventory Dashboard" \
                --text="📦 Real-Time Medicine Stock Overview" \
                --width=900 \
                --height=550 \
                --column="Medicine Name" \
                --column="Category" \
                --column="Stock" \
                --column="Price" \
                --column="Expiry Status" \
                --column="Restricted Status" \
                --ok-label="🔍 Close"
}

# To check the Blood inventory
viewBloodInventory() {
        getCount() {
                count=$(grep "^$1|" "$BLOOD" | cut -d '|' -f2)
                echo "${count:-0}"
        }

        (
                echo "A+"; echo "$(getCount A+)"
                echo "A-"; echo "$(getCount A-)"
                echo "B+"; echo "$(getCount B+)"
                echo "B-"; echo "$(getCount B-)"
                echo "O+"; echo "$(getCount O+)"
                echo "O-"; echo "$(getCount O-)"
                echo "AB+"; echo "$(getCount AB+)"
                echo "AB-"; echo "$(getCount AB-)"
        ) | zenity --list \
                --title="🩸 LifeLine Blood Bank Dashboard" \
                --text="🧬 Real-Time Blood Unit Availability" \
                --width=700 \
                --height=500 \
                --column="Blood Group" \
                --column="Units Available" \
                --ok-label="🔍 Close"
}

# Check meds expire so that staff accediently dont issue expired meds
isExpired() {
    line=$(grep -i "^$1|" "$MEDS")

    if [[ -z "$line" ]]; then
        return
    fi

    expDate=$(echo "$line" | cut -d '|' -f5)
    # Convert MM/DD/YYYY → YYYY-MM-DD if needed
    if [[ "$expDate" =~ ^[0-9]{2}/[0-9]{2}/[0-9]{4}$ ]]; then
        month=$(echo "$expDate" | cut -d '/' -f1)
        day=$(echo "$expDate" | cut -d '/' -f2)
        year=$(echo "$expDate" | cut -d '/' -f3)
        expDate="$year-$month-$day"
    fi

    today=$(date +%F)
    # Compare as strings, works now because both are YYYY-MM-DD
    if [[ "$expDate" < "$today" ]]; then
        zenity --error --text="Medicine Expired!\n\nExpiry Date: $expDate"
        writeLog "WARNING" "Expired medicine access blocked: $1"
        expiredFlag=1
        return
    fi

    expiredFlag=0
    return
}

# Issue meds for the patient by the staff
issueMeds() {
        target=$(zenity --entry \
                --title="💊 Issue Item" \
                --text="Enter Medicine or Blood Name (e.g., A+):")
        if [[ -z "$target" ]]; then
                return
        fi

        # Check if target is a medicine
        line=$(grep -i "^$target|" "$MEDS")
        if [[ -n "$line" ]]; then
                n=$(echo "$line" | cut -d '|' -f1)
                cate=$(echo "$line" | cut -d '|' -f2)
                q=$(echo "$line" | cut -d '|' -f3)
                r=$(echo "$line" | cut -d '|' -f6)
                exp=$(echo "$line" | cut -d '|' -f5)

                # Expiry check
                expiredFlag=0
                isExpired "$n"

                if [[ "$expiredFlag" -eq 1 ]]; then
                        return
                fi

                # Restricted medicine check
                if [[ "$r" == "Yes" ]] && [[ "$activeRole" != "Pharmacist" ]]; then
                        zenity --warning \
                               --title="🚫 Access Denied" \
                               --text="$n is a restricted medicine.\nRequest a Pharmacist for access."
                        writeLog "SECURITY" "Access Denied: $n requested by $activeUser"
                        return
                fi

                # Patient name
                patientName=$(zenity --entry \
                        --title="👤 Patient Information" \
                        --text="Enter Patient Name:")
                if [[ -z "$patientName" ]]; then
                        zenity --error --text="Patient Name is required!"
                        return
                fi

                # Quantity
                askQty=$(zenity --entry \
                        --title="🔢 Quantity to Issue" \
                        --text="Available Stock: $q\nEnter Quantity to Issue:")
                if [[ ! "$askQty" =~ ^[0-9]+$ ]] || [[ "$askQty" -le 0 ]] || [[ "$askQty" -gt "$q" ]]; then
                        zenity --error --text="Invalid quantity or insufficient stock!"
                        return
                fi

                # Update inventory
                remaining=$((q - askQty))
                grep -v "^$n|" "$MEDS" > "$MEDS.tmp"
                price=$(echo "$line" | cut -d '|' -f4)
                rest=$(echo "$line" | cut -d '|' -f6)
                echo "$n|$cate|$remaining|$price|$exp|$rest" >> "$MEDS.tmp"
                mv "$MEDS.tmp" "$MEDS"

                # Log and success message
                writeLog "ISSUE" "Issued $askQty units of $n ($cate) to Patient: $patientName"
                zenity --info \
                        --title="✅ Transaction Approved" \
                        --text="Medicine: $n\nQuantity: $askQty\nPatient: $patientName\nInventory Updated."

        else
                # Blood issue
                target=$(echo "$target" | tr -d ',[:space:]')
                line=$(grep -i "^$target|" "$BLOOD")
                if [[ -z "$line" ]]; then
                        zenity --error --text="Error: '$target' not found in inventory!"
                        return
                fi

                bloodType=$(echo "$line" | cut -d '|' -f1)
                qty=$(echo "$line" | cut -d '|' -f2)

                patientName=$(zenity --entry \
                        --title="👤 Patient Name" \
                        --text="Enter Patient Name for Blood:")
                if [[ -z "$patientName" ]]; then
                        zenity --error --text="Patient Name is required!"
                        return
                fi

                askQty=$(zenity --entry \
                        --title="🔢 Units to Issue" \
                        --text="Available Stock: $qty\nEnter Units to Issue:")
                if [[ ! "$askQty" =~ ^[0-9]+$ ]] || [[ "$askQty" -le 0 ]] || [[ "$askQty" -gt "$qty" ]]; then
                        zenity --error --text="Invalid quantity or insufficient stock!"
                        return
                fi

                remaining=$((qty - askQty))
                grep -v "^$bloodType|" "$BLOOD" > "$BLOOD.tmp"
                echo "$bloodType|$remaining" >> "$BLOOD.tmp"
                mv "$BLOOD.tmp" "$BLOOD"

                writeLog "ISSUE" "Issued $askQty units of blood $bloodType to Patient: $patientName"
                zenity --info \
                        --title="✅ Blood Issued" \
                        --text="Blood Type: $bloodType\nUnits: $askQty\nPatient: $patientName\nInventory Updated."
        fi
}

# To handle request for the restricted meds
requestMeds() {
        med=$(zenity --entry \
                --title="🚨 Restricted Medicine Request" \
                --text="Enter Medicine Name:")
        if [[ -z "$med" ]]; then
                return
        fi

        line=$(grep -i "^$med|" "$MEDS")
        if [[ -z "$line" ]]; then
                zenity --error \
                        --title="❌ Not Found" \
                        --text="Medicine '$med' not found in inventory!"
                return
        fi

        expiredFlag=0
        isExpired "$med"

        if [[ "$expiredFlag" -eq 1 ]]; then
                return
        fi

        restriction=$(echo "$line" | cut -d '|' -f6)
        if [[ "$restriction" != "Yes" ]]; then
                zenity --info \
                        --title="ℹ️ Not Restricted" \
                        --text="This medicine is not restricted.\n\nYou can issue it normally."
                return
        fi

        patient=$(zenity --entry \
                --title="👤 Patient Details" \
                --text="Enter Patient Name:")
        if [[ -z "$patient" ]]; then
                return
        fi

        qty=$(zenity --entry \
                --title="💊 Quantity Request" \
                --text="Enter Quantity:")
        if [[ ! "$qty" =~ ^[0-9]+$ ]]; then
                zenity --error \
                        --title="⚠️ Invalid Input" \
                        --text="Please enter a valid numeric quantity!"
                return
        fi

        # Confirmation dialog (NEW - makes it feel professional)
        zenity --question \
                --title="Confirm Request" \
                --text="Submit request?\n\nMedicine: $med\nPatient: $patient\nQuantity: $qty"

        if [[ $? -ne 0 ]]; then
                return
        fi

        echo "$(date +%F)|$activeUser|$patient|$med|$qty|DENIED" >> "$EMERGENCY"

        writeLog "REQUEST" \
                "Restricted medicine requested: $med Qty:$qty Patient:$patient Status:DENIED"

        zenity --info \
                --title="✅ Request Submitted" \
                --text="Request sent successfully!\n\nStatus: ⏳ Pending Pharmacist Approval"
}

# Response of the restricted meds --> this is for Pharmacist
respondReq() {
        while true; do
                req=$(grep '|DENIED$' "$EMERGENCY" | head -n 1)

                if [[ -z "$req" ]]; then
                        zenity --info \
                                --title="📭 No Pending Requests" \
                                --text="There are currently no restricted medicine requests waiting for approval." \
                                --width=450 --height=200

                      (
                        while IFS='|' read -r date req patient med qty status || [ -n "$date" ]; do
                                echo "$date"
                                echo "$req"
                                echo "$patient"
                                echo "$med"
                                echo "$qty"
                                echo "$status"
                        done < "$EMERGENCY"
               		 )  | zenity --list \
                      		--title="🚨 LifeLine Emergency Requests Dashboard" \
                       		--text="📋 Pending & Past Restricted Medicine Requests" \
                        	--width=900 \
                        	--height=550 \
                        	--column="Date" \
                        	--column="Requested By" \
                        	--column="Patient" \
                        	--column="Medicine" \
                        	--column="Quantity" \
                        	--column="Status" \
                        	--ok-label="🔍 Close"
                        break
                fi

                date=$(echo "$req" | cut -d '|' -f1)
                staff=$(echo "$req" | cut -d '|' -f2)
                patient=$(echo "$req" | cut -d '|' -f3)
                med=$(echo "$req" | cut -d '|' -f4)
                qty=$(echo "$req" | cut -d '|' -f5)

                zenity --question \
                        --title="🚨 Restricted Medicine Approval" \
                        --width=500 --height=350 \
                        --text="📅 Date       : $date
👨‍⚕️ Requested By : $staff
🧑 Patient    : $patient
💊 Medicine   : $med
📦 Quantity   : $qty

━━━━━━━━━━━━━━━━━━━━━━
Do you want to APPROVE and ISSUE this request?" \
                        --ok-label="✅ APPROVE & ISSUE" \
                        --cancel-label="❌ REJECT"

                decision=$?

                grep -v "^$req$" "$EMERGENCY" > "$EMERGENCY.tmp"

                if [[ "$decision" -eq 0 ]]; then
                        line=$(grep -i "^$med|" "$MEDS")

                        if [[ -z "$line" ]]; then
                                zenity --error \
                                        --title="❌ Error" \
                                        --text="Medicine not found in inventory!"
                                echo "$req" >> "$EMERGENCY.tmp"

                        else
                                stock=$(echo "$line" | cut -d '|' -f3)

                                if [[ "$qty" -gt "$stock" ]]; then
                                        zenity --error \
                                                --title="⚠️ Stock Error" \
                                                --text="Insufficient stock to issue this request!"
                                        echo "$req" >> "$EMERGENCY.tmp"

                                else
                                        remaining=$((stock - qty))
                                        grep -v "^$med|" "$MEDS" > "$MEDS.tmp"

                                        cate=$(echo "$line" | cut -d '|' -f2)
                                        price=$(echo "$line" | cut -d '|' -f4)
                                        exp=$(echo "$line" | cut -d '|' -f5)
                                        rest=$(echo "$line" | cut -d '|' -f6)

                                        echo "$med|$cate|$remaining|$price|$exp|$rest" >> "$MEDS.tmp"
                                        mv "$MEDS.tmp" "$MEDS"

                                        echo "$date|$staff|$patient|$med|$qty|ISSUED" >> "$EMERGENCY.tmp"

                                        writeLog "ISSUE" \
                                                "Issued $qty units of $med (Category : $cate) to Patient: $patient"

                                        zenity --info \
                                                --title="✅ Request Approved" \
                                                --text="Medicine successfully issued!\n\n💊 $med\n📦 Quantity: $qty\n🧑 Patient: $patient" \
                                                --width=450 --height=250
                                fi
                        fi
                else
                        echo "$date|$staff|$patient|$med|$qty|REJECTED" >> "$EMERGENCY.tmp"

                        writeLog "PHARMACY" \
                                "Restricted request REJECTED: $med Qty:$qty Patient:$patient"

                        zenity --warning \
                                --title="❌ Request Rejected" \
                                --text="The request has been rejected.\n\n💊 $med\n🧑 Patient: $patient" \
                                --width=450 --height=250
                fi

                mv "$EMERGENCY.tmp" "$EMERGENCY"
       			(
    				while IFS='|' read -r date req patient med qty status || [ -n "$date" ]; do
        				echo "$date"
       					echo "$req"
        				echo "$patient"
        				echo "$med"
        				echo "$qty"
        				echo "$status"
    				done < "$EMERGENCY"
				) | zenity --list \
    					--title="🚨 LifeLine Emergency Requests Dashboard" \
    					--text="📋 Pending & Past Restricted Medicine Requests" \
    					--width=900 \
    					--height=550 \
    					--column="Date" \
    					--column="Requested By" \
    					--column="Patient" \
    					--column="Medicine" \
    					--column="Quantity" \
    					--column="Status" \
    					--ok-label="🔍 Close"
        done
}


# Search in the log file to find desired activity or meds usage
searchLog() {
        keyword=$(zenity --entry \
                --title="🔎 LifeLine Log Search" \
                --text="Enter Keyword (Patient / Date / Action):")

        if [[ -z "$keyword" ]]; then
                return
        fi

        if ! grep -qi "$keyword" "$LOG"; then
                zenity --warning \
                        --title="No Results Found" \
                        --text="❌ No matching logs found for:\n\n'$keyword'"
                return
        fi

        (
                grep -i "$keyword" "$LOG" | while IFS='|' read -r date user action details
                do
                        echo "$date"
                        echo "$action"
                        echo "$user"
                        echo "$details"
                done
        ) | zenity --list \
                --title="📜 LifeLine Audit Logs" \
                --text="Showing results for: '$keyword'" \
                --width=900 \
                --height=550 \
                --column="📅 Date" \
                --column="👤 User" \
                --column="⚙️ Action" \
                --column="📝 Details" \
                --ok-label="Close"
}

# As name says this make a staff register but only admin can make it
registerAccount() {
        role=$(zenity --list \
                --title="Select Account Type" \
                --column="Role" \
                "Staff" \
                "Pharmacist")

        if [[ -z "$role" ]]; then
			return
		fi

        regData=$(zenity --forms --title="Create Account ($role)" \
                --add-entry="Enter Username : " \
                --add-password="Create a Password : " \
                --add-password="Confirm Password : ")

        if [[ -z "$regData" ]]; then
			return
		fi

        u=$(echo "$regData" | cut -d '|' -f1)
        p1=$(echo "$regData" | cut -d '|' -f2)
        p2=$(echo "$regData" | cut -d '|' -f3)
        if [[ -z "$u" || -z "$p1" || "$p1" != "$p2" ]]; then
                zenity --error --text="Validation Failed! Password mismatch or empty fields."
                return
        fi

        if grep -q "^$u|" "$USER"; then
                zenity --error --text="Username already exists!"
                return
        fi

        echo "$u|$p1|$role" >> "$USER"

        zenity --info --text="Account Created Successfully!\n\nUser: $u\nRole: $role"
        writeLog "USER ADDITION" "New $role Account Created: $u"
}

# This make the staff to change their password as admin create their password 1st time
changeUserPass() {
        newPass=$(zenity --password --title="Update Password" --text="Enter New Password : ")
        if [[ -n "$newPass" ]]; then
                nowRole=$(grep "^$activeUser|" "$USER" | cut -d '|' -f3)
                grep -v "^$activeUser|" "$USER" > "$USER.tmp"
                echo "$activeUser|$newPass|$nowRole" >> "$USER.tmp"
                mv "$USER.tmp" "$USER"
                zenity --info --text="Password Updated Successfully!"
                writeLog "AUTHENTICATION" "User Updated Their Password!"
        fi
}

# This is the menu where pharmacist Oparates
pharmaMenu() {
        lowStock

        while true; do
                if grep -q '|DENIED$' "$EMERGENCY"; then
                        reqStatus="🔴 Emergency Requests Pending"
                else
                        reqStatus="🟢 System Normal - No Pending Requests"
                fi

                choice=$(zenity --list \
                        --title="🩺 LifeLine Pharmacist Dashboard" \
                        --text="Welcome, $activeUser\n\n$reqStatus\n\nSelect an operation:" \
                        --width=600 --height=600 \
                        --column="Module" --column="Description" \
                        "💊 MEDICINE MANAGEMENT" "Add / Update Medicines Inventory" \
                        "🩸 BLOOD BANK" "Manage Blood Stock & Availability" \
                        "🧑‍🤝‍🧑 DONOR SYSTEM" "Register & Manage Donors" \
                        "💰 BILLING SYSTEM" "Generate Patient Bills & Invoices" \
                        "📊 SYSTEM STATUS" "Run Health Check & Alerts" \
                        "🚨 EMERGENCY REQUESTS" "Approve / Reject Restricted Requests" \
                        "👥 USER MANAGEMENT" "Add Staff & Assign Roles" \
                        "🔍 AUDIT LOGS" "Search System Activities" \
                        "💾 BACKUP SYSTEM" "Export Full Database Backup" \
                        "🔑 CHANGE PASSWORD" "Update Your Password" \
                        "🚪 LOGOUT" "Securely Exit Session")

                case "$choice" in
                        "💊 MEDICINE MANAGEMENT") addMeds ;;
                        "🩸 BLOOD BANK") viewBloodInventory ;;
                        "🧑‍🤝‍🧑 DONOR SYSTEM") manageDonors ;;
                        "💰 BILLING SYSTEM") generateBill ;;
                        "📊 SYSTEM STATUS") healthCheck ;;
                        "🚨 EMERGENCY REQUESTS") respondReq ;;
                        "👥 USER MANAGEMENT") registerAccount "User" ;;
                        "🔍 AUDIT LOGS") searchLog ;;
                        "💾 BACKUP SYSTEM")
                                zip -r "$BACKUP/dbBackup$(date +%s).zip" "$DB"
                                zenity --info \
                                        --title="✅ Backup Completed" \
                                        --text="Database backup saved successfully.\n\nLocation: $BACKUP"
                                ;;

                        "🔑 CHANGE PASSWORD") changeUserPass ;;
                        "🚪 LOGOUT") break ;;
                        *) break ;;
                esac
        done
}


# Staff menu where Stuff oparates
staffMenu() {
        while true; do
                choice=$(zenity --list \
                        --title="🩺 LifeLine Staff Dashboard - $activeUser" \
                        --text="Select a service to continue" \
                        --width=520 --height=520 \
                        --column="Option" --column="Service Description" \
                        "📦 VIEW INVENTORY" "Check Current Pharmacy Stock" \
                        "💊 ISSUE MEDICINE" "Request & Issue Medicine" \
                        "🩸 BLOOD BANK" "Check Blood Availability" \
                        "🧑‍🤝‍🧑 DONOR LIST" "View Registered Donors" \
                        "⚠️ REQUEST RESTRICTED" "Request Restricted Medicine" \
                        "💰 FINANCE" "View Patient Billing Records" \
                        "🔍 SEARCH LOGS" "Search System Activities" \
                        "🔑 CHANGE PASSWORD" "Update Your Password" \
                        "🚪 LOGOUT" "Exit Staff Portal")

                case "$choice" in
                        "📦 VIEW INVENTORY") viewInventory ;;
                        "💊 ISSUE MEDICINE") issueMeds ;;
                        "🩸 BLOOD BANK") viewBloodInventory ;;
                        "🧑‍🤝‍🧑 DONOR LIST")
                                if [[ ! -s "$DONOR" ]]; then
                                        zenity --info \
                                                --title="Donor List" \
                                                --text="No donors registered yet."
                                        continue
                                fi

                                donorList=()

                                while IFS='|' read -r name blood phone date
                                do
                                        donorList+=("$name" "$blood" "$phone" "$date")
                                done < "$DONOR"

                                zenity --list \
                                        --title="🧑‍🤝‍🧑 Registered Blood Donors" \
                                        --width=700 \
                                        --height=500 \
                                        --column="Name" \
                                        --column="Blood Group" \
                                        --column="Phone" \
                                        --column="Last Donation" \
                                "${donorList[@]}"
                                ;;

                        "⚠️ REQUEST RESTRICTED") requestMeds ;;
                        "💰 FINANCE")
                                if [[ ! -s "$BILL" ]]; then
                                        zenity --info \
                                                --title="Finance Records" \
                                                --text="No billing records available."
                                        continue
                                fi

                                billList=()

                                while IFS='|' read -r date patient type amount
                                do
                                        billList+=("$date" "$patient" "$type" "$amount")
                                done < "$BILL"

                                zenity --list \
                                        --title="💰 Billing History" \
                                        --width=750 \
                                        --height=500 \
                                        --column="Date" \
                                        --column="Patient" \
                                        --column="Type" \
                                        --column="Amount" \
                                "${billList[@]}"
                                ;;

                        "🔍 SEARCH LOGS") searchLog ;;
                        "🔑 CHANGE PASSWORD") changeUserPass ;;
                        "🚪 LOGOUT") break ;;
                        *) break ;;
                esac
        done
}

# Main method which run 1st then rely to the other methodes
lifeLine() {
        dataBase
        if [[ ! -s "$USER" ]]; then
                zenity --info \
                        --title="🩺 LifeLine Setup" \
                        --text="Welcome to LifeLine System\n\nFirst Time Setup Required!\n\nRegister as Admin Pharmacist."
                registerAccount "Pharmacist"
        fi

        while true; do
                loginRaw=$(zenity --forms \
                        --title="🩺 LifeLine Secure Login" \
                        --text="🔐 Enter your credentials to continue\n" \
                        --width=450 --height=300 \
                        --add-entry="👤 Username" \
                        --add-password="🔑 Password" \
                        --add-combo="🧑⚕️ Role" \
                        --combo-values="Pharmacist|Staff" \
                        --combo-values="Staff" )

                if [[ -z "$loginRaw" ]]; then
                        exit 0
                fi

                uLog=$(echo "$loginRaw" | cut -d'|' -f1)
                pLog=$(echo "$loginRaw" | cut -d'|' -f2)
                rLog=$(echo "$loginRaw" | cut -d'|' -f3)

                match=$(grep "^$uLog|$pLog|" "$USER")

                if [[ -n "$match" ]]; then
                        actualRole=$(echo "$match" | cut -d'|' -f3)

                        # Role validation
                        if [[ "$rLog" != "$actualRole" ]]; then
                                zenity --error \
                                        --title="❌ Role Mismatch" \
                                        --text="Incorrect Role Selected!\n\nYou are registered as: $actualRole"
                                writeLog "AUTHENTICATION" "Role mismatch for $uLog"
                                continue
                        fi

                        activeUser="$uLog"
                        activeRole="$actualRole"

                        zenity --info \
                                --title="✅ Login Successful" \
                                --text="Welcome, $activeUser!\nRole: $activeRole"

                        writeLog "AUTHENTICATION" "Successful Login"

                        if [[ "$activeRole" == "Pharmacist" ]]; then
                                pharmaMenu
                        else
                                staffMenu
                        fi
                else
                        zenity --error \
                                --title="🚫 Access Denied" \
                                --text="Invalid Username or Password!"
                        writeLog "AUTHENTICATION" "Failed Login Attempt : $uLog"
                fi
        done
}

# Call the main method
lifeLine
